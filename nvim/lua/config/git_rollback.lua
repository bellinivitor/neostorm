-- Rollback de arquivos inteiros (painel de alterações do git), como no PhpStorm:
--   arquivo alterado/apagado -> volta para a versão do último commit
--   arquivo novo             -> é apagado (com confirmação)
local M = {}

local function git(args, cwd)
  local cmd = { "git" }
  vim.list_extend(cmd, args)
  return vim.system(cmd, { cwd = cwd, text = true }):wait()
end

local function dir_of(path)
  return vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ":h")
end

-- Lista as alterações em `path` (arquivo ou pasta): { { path=abs, x=, y= , new=bool } }
function M.changes(path)
  local cwd = dir_of(path)
  local root = vim.trim(git({ "rev-parse", "--show-toplevel" }, cwd).stdout or "")
  if root == "" then return nil, "não é um repositório git" end
  local res = git({ "status", "--porcelain=v1", "-z", "--untracked-files=all", "--", path }, cwd)
  local out, tokens = {}, vim.split(res.stdout or "", "\0", { plain = true, trimempty = true })
  local i = 1
  while i <= #tokens do
    local t = tokens[i]
    local x, y, rel = t:sub(1, 1), t:sub(2, 2), t:sub(4)
    local item = { path = root .. "/" .. rel, x = x, y = y }
    item.new = (x == "?" or x == "A")
    if x == "R" or x == "C" then
      -- renomeado: o caminho novo é tratado como arquivo novo; o antigo volta do commit
      item.new = true
      i = i + 1
      table.insert(out, { path = root .. "/" .. tokens[i], x = "D", y = " ", new = false })
    end
    table.insert(out, item)
    i = i + 1
  end
  return out, nil, root
end

local function refresh()
  vim.cmd("silent! checktime")
  pcall(function() require("neo-tree.sources.manager").refresh("git_status") end)
  pcall(function() require("neo-tree.sources.manager").refresh("filesystem") end)
end

function M.rollback(path, opts)
  opts = opts or {}
  local list, err, root = M.changes(path)
  if not list then return vim.notify("Rollback: " .. err, vim.log.levels.WARN) end
  if #list == 0 then return vim.notify("Nenhuma alteração em " .. vim.fn.fnamemodify(path, ":t"), vim.log.levels.INFO) end

  local tracked, new = {}, {}
  for _, c in ipairs(list) do table.insert(c.new and new or tracked, c) end

  local name = vim.fn.fnamemodify(path, ":.")
  local msg = (#list == 1) and ("Desfazer as alterações de " .. name .. "?")
    or ("Desfazer as alterações de " .. #list .. " arquivos em " .. name .. "?")
  if #new > 0 then
    msg = msg .. "\n\n" .. (#new == 1 and "1 arquivo novo será APAGADO:" or (#new .. " arquivos novos serão APAGADOS:"))
    for k, c in ipairs(new) do
      if k > 5 then msg = msg .. "\n  ..." break end
      msg = msg .. "\n  " .. vim.fn.fnamemodify(c.path, ":.")
    end
  end
  if not opts.force and vim.fn.confirm(msg, "&Rollback\n&Cancelar", 2, "Question") ~= 1 then return end

  if #tracked > 0 then
    local args = { "restore", "--source=HEAD", "--staged", "--worktree", "--" }
    for _, c in ipairs(tracked) do table.insert(args, c.path) end
    local r = git(args, root)
    if r.code ~= 0 then return vim.notify("Rollback falhou: " .. (r.stderr or ""), vim.log.levels.ERROR) end
  end
  for _, c in ipairs(new) do
    if c.x == "A" or c.x == "R" or c.x == "C" then git({ "rm", "-q", "-f", "--cached", "--", c.path }, root) end
    -- fecha o arquivo se estiver aberto e apaga
    local b = vim.fn.bufnr(c.path)
    if b ~= -1 then pcall(vim.api.nvim_buf_delete, b, { force = true }) end
    vim.fn.delete(c.path)
  end

  refresh()
  vim.notify(("Rollback feito: %d arquivo(s)"):format(#list), vim.log.levels.INFO)
end

-- Janela de código (não flutuante, sem painel/terminal); cria uma se não houver
local function editor_win()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.api.nvim_win_get_config(w).relative == "" and vim.bo[b].buftype == "" then return w end
  end
  -- só tem o painel aberto: cria uma janela à esquerda dele
  vim.cmd("topleft vnew")
  return vim.api.nvim_get_current_win()
end

-- Comparação no estilo PhpStorm, numa tela própria (tabpage):
--   esquerda = último commit (HEAD, só leitura) | direita = sua versão (editável)
--   verde = linha nova · vermelho = linha apagada · azul = linha alterada
--   q, Esc ou Cmd+W fecham e voltam para onde você estava
function M.diff(path)
  if vim.fn.filereadable(path) == 0 then
    return vim.notify("O arquivo foi apagado; use Rollback para trazê-lo de volta", vim.log.levels.INFO)
  end
  -- Versão do último commit (vazia se o arquivo é novo)
  local cwd = vim.fn.fnamemodify(path, ":h")
  local name = vim.fn.fnamemodify(path, ":t")
  local res = git({ "show", "HEAD:./" .. name }, cwd)
  local is_new = res.code ~= 0
  local old = is_new and {} or vim.split(res.stdout or "", "\n", { plain = true })
  if #old > 0 and old[#old] == "" then table.remove(old) end
  local rel = vim.fn.fnamemodify(path, ":.")

  -- Tela própria para a comparação
  vim.cmd("tabnew")
  local tab = vim.api.nvim_get_current_tabpage()
  vim.t.rollback_diff = true
  local scratch = vim.api.nvim_get_current_buf()

  -- Direita: sua versão
  local win = vim.api.nvim_get_current_win()
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    vim.api.nvim_win_set_buf(win, buf)
  else
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    buf = vim.api.nvim_get_current_buf()
  end
  if vim.api.nvim_buf_is_valid(scratch) and scratch ~= buf then pcall(vim.api.nvim_buf_delete, scratch, { force = true }) end
  vim.cmd("diffthis")

  -- Esquerda: último commit
  vim.cmd("aboveleft vnew")
  local head = vim.api.nvim_get_current_buf()
  local head_win = vim.api.nvim_get_current_win()
  vim.b[head].rollback_head = true
  vim.api.nvim_buf_set_lines(head, 0, -1, false, old)
  vim.bo[head].buftype = "nofile"
  vim.bo[head].bufhidden = "wipe"
  vim.bo[head].buflisted = false
  vim.bo[head].swapfile = false
  vim.bo[head].modifiable = false
  vim.bo[head].filetype = vim.bo[buf].filetype
  pcall(vim.api.nvim_buf_set_name, head, "HEAD:" .. rel)
  vim.cmd("diffthis")

  -- Aparência das duas colunas
  for _, w in ipairs({ head_win, win }) do
    local wo = vim.wo[w]
    wo.foldenable = false       -- arquivo inteiro, sem esconder trechos iguais
    wo.foldcolumn = "0"
    wo.number = true
    wo.cursorline = true
    wo.scrollbind = true
    wo.cursorbind = true
  end
  vim.wo[head_win].statuscolumn = ""   -- números normais na versão antiga
  -- Do lado antigo, "só existe aqui" = linha apagada (vermelho); do lado novo = linha nova (verde)
  vim.wo[head_win].winhighlight = "DiffAdd:DiffOldOnly,DiffDelete:DiffFiller"
  vim.wo[win].winhighlight = "DiffAdd:DiffNewOnly,DiffDelete:DiffFiller"
  vim.wo[head_win].winbar = "%#DiffHeaderOld# \u{F0718}  Último commit (HEAD) %*%#Comment# só leitura  %<" .. rel .. "%*"
  vim.wo[win].winbar = "%#DiffHeaderNew# \u{F03EB}  Sua versão %*%#Comment#" .. (is_new and " arquivo novo " or "")
    .. "  %<" .. rel .. "%=q fecha  %*"

  -- Fechar a comparação: fecha a tela própria e volta para onde estava
  local group = vim.api.nvim_create_augroup("rollback_diff_" .. head, { clear = true })
  local closed = false
  local function close_diff()
    if closed then return end
    closed = true
    vim.schedule(function()
      pcall(vim.api.nvim_del_augroup_by_id, group)
      for _, lhs in ipairs({ "q", "<Esc>", "<D-w>" }) do pcall(vim.keymap.del, "n", lhs, { buffer = buf }) end
      for _, w in ipairs(vim.fn.win_findbuf(buf)) do
        pcall(vim.api.nvim_win_call, w, function()
          vim.cmd("diffoff")
          vim.wo.scrollbind, vim.wo.cursorbind = false, false
          vim.wo.winhighlight, vim.wo.winbar = "", ""
        end)
      end
      if vim.api.nvim_tabpage_is_valid(tab) then
        local n = vim.api.nvim_tabpage_get_number(tab)
        pcall(vim.cmd, "tabclose " .. n)
      end
    end)
  end
  for _, b in ipairs({ head, buf }) do
    for _, lhs in ipairs({ "q", "<Esc>", "<D-w>" }) do
      vim.keymap.set("n", lhs, close_diff, { buffer = b, nowait = true, desc = "Fechar diff" })
    end
  end
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufHidden" }, { group = group, buffer = head, callback = close_diff })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      local w = tonumber(ev.match)
      if w == head_win or w == win then close_diff() end
    end,
  })
  vim.api.nvim_create_autocmd("TabClosed", { group = group, callback = close_diff })

  -- começa na primeira diferença, na sua versão
  vim.api.nvim_set_current_win(win)
  vim.cmd("normal! gg")
  pcall(vim.cmd, "normal! ]c")
end

-- Funções para o neo-tree (recebem o `state` do painel)
local function node_path(state)
  local node = state.tree:get_node()
  if not node or node.type == "message" then return nil end
  return node.path, node
end

function M.tree_rollback(state)
  local path = node_path(state)
  if path then M.rollback(path) end
end

function M.tree_diff(state)
  local path, node = node_path(state)
  if path and node.type ~= "directory" then M.diff(path) end
end

function M.tree_menu(state)
  local path, node = node_path(state)
  if not path then return end
  local items = {}
  if node.type ~= "directory" then
    table.insert(items, { label = "\u{F0EC6}  Ver diff", key = "d", run = function() M.diff(path) end })
  end
  table.insert(items, { label = "\u{F054C}  Rollback", key = "r", hint = "⌥⌘Z", run = function() M.rollback(path) end })
  require("config.popup_menu").open(items, { mouse = true })
end

-- Botão direito (global): no painel da direita abre o menu Ver diff / Rollback;
-- em qualquer outro lugar abre o menu padrão do Neovim
function M.right_click()
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or pos.line == 0 then return end
  local buf = vim.api.nvim_win_get_buf(pos.winid)
  vim.api.nvim_set_current_win(pos.winid)
  pcall(vim.api.nvim_win_set_cursor, pos.winid, { pos.line, math.max(pos.column - 1, 0) })
  if vim.bo[buf].filetype == "commit_list" then
    return require("config.commit").menu(pos.line)
  end
  if vim.bo[buf].filetype == "neo-tree" then
    local ok, state = pcall(require("neo-tree.sources.manager").get_state_for_window, pos.winid)
    if ok and state and state.tree then return M.tree_menu(state) end
  end
  pcall(vim.cmd, "popup PopUp")
end

return M
