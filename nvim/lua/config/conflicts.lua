-- Conflitos de merge, rebase, cherry-pick e revert, como no PhpStorm:
--
-- No arquivo: cada bloco em conflito ganha cor (um lado verde, o outro azul) e, na linha
-- do <<<<<<<, os atalhos para resolver:
--   co usar o lado de cima (HEAD) · ct usar o lado de baixo · cb usar os dois · c0 nenhum
--   ]x / [x próximo / anterior · Alt+Enter no bloco abre o mesmo menu
-- Quando o último bloco do arquivo é resolvido, o arquivo é salvo e marcado como
-- resolvido (git add).
--
-- Janela de conflitos (<leader>gx, :Conflitos; abre sozinha quando um merge para):
--   Enter abre o arquivo no primeiro conflito · o/t usa um lado no arquivo inteiro
--   a marca como resolvido · c continua o merge/rebase · x aborta · q fecha
local M = {}

local ns = vim.api.nvim_create_namespace("git_conflicts")
local I = { file = "\u{F0214}", warn = "\u{F0026}", ok = "\u{F012C}", merge = "\u{F062D}" }

local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "Conflitos" }) end

local function repo_root(path)
  local dir = path and path ~= "" and vim.fn.fnamemodify(path, ":h") or vim.fn.getcwd()
  local r = vim.system({ "git", "rev-parse", "--show-toplevel" }, { cwd = dir, text = true }):wait()
  return r.code == 0 and vim.trim(r.stdout) or nil
end

local function git(root, args)
  local cmd = { "git" }
  vim.list_extend(cmd, args)
  local r = vim.system(cmd, { cwd = root, text = true }):wait()
  return r.code == 0, vim.trim((r.stdout or "") .. "\n" .. (r.stderr or ""))
end

-- ---------------------------------------------------------------------------
-- Estado do repositório
-- ---------------------------------------------------------------------------
--- Arquivos ainda em conflito (caminhos relativos à raiz)
function M.files(root)
  local ok, out = git(root, { "diff", "--name-only", "--diff-filter=U" })
  if not ok then return {} end
  return vim.split(out, "\n", { trimempty = true })
end

local function git_path(root, name)
  local _, out = git(root, { "rev-parse", "--git-path", name })
  local p = vim.split(out, "\n", { trimempty = true })[1] or ""
  return p:sub(1, 1) == "/" and p or (root .. "/" .. p)
end

--- Operação em andamento: merge, rebase, cherry-pick, revert (ou nil)
function M.operation(root)
  if vim.uv.fs_stat(git_path(root, "rebase-merge")) or vim.uv.fs_stat(git_path(root, "rebase-apply")) then return "rebase" end
  if vim.uv.fs_stat(git_path(root, "MERGE_HEAD")) then return "merge" end
  if vim.uv.fs_stat(git_path(root, "CHERRY_PICK_HEAD")) then return "cherry-pick" end
  if vim.uv.fs_stat(git_path(root, "REVERT_HEAD")) then return "revert" end
end

local OP_LABEL = { merge = "Merge", rebase = "Rebase", ["cherry-pick"] = "Cherry-pick", revert = "Revert" }

-- ---------------------------------------------------------------------------
-- Blocos em conflito dentro do arquivo
-- ---------------------------------------------------------------------------
--- { start, base, mid, finish (linhas, 1-based), ours, theirs (rótulos) }
local function blocks(buf)
  local out, cur = {}, nil
  for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if l:match("^<<<<<<<") then
      cur = { start = i, ours = vim.trim(l:sub(8)) }
    elseif cur and l:match("^|||||||") then
      cur.base = i
    elseif cur and l:match("^=======%s*$") then
      cur.mid = i
    elseif cur and cur.mid and l:match("^>>>>>>>") then
      cur.finish, cur.theirs = i, vim.trim(l:sub(8))
      table.insert(out, cur)
      cur = nil
    end
  end
  return out
end

local function short(label, fallback)
  label = label ~= "" and label or fallback
  return #label > 28 and (label:sub(1, 27) .. "…") or label
end

local function render(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local list = blocks(buf)
  for _, b in ipairs(list) do
    local function line_hl(from, to, hl)
      for l = from, to do vim.api.nvim_buf_set_extmark(buf, ns, l - 1, 0, { line_hl_group = hl, priority = 20 }) end
    end
    line_hl(b.start, b.start, "ConflictMarker")
    line_hl(b.start + 1, (b.base or b.mid) - 1, "ConflictOurs")
    if b.base then line_hl(b.base, b.mid - 1, "ConflictBase") end
    line_hl(b.mid, b.mid, "ConflictMarker")
    line_hl(b.mid + 1, b.finish - 1, "ConflictTheirs")
    line_hl(b.finish, b.finish, "ConflictMarker")
    -- atalhos no fim da linha do <<<<<<<
    local function key(k) return { " " .. k .. " ", "ConflictKey" } end
    vim.api.nvim_buf_set_extmark(buf, ns, b.start - 1, 0, {
      virt_text = {
        { "   " }, key("co"), { " usar " .. short(b.ours, "o de cima") .. "   ", "ConflictHintOurs" },
        key("ct"), { " usar " .. short(b.theirs, "o de baixo") .. "   ", "ConflictHintTheirs" },
        key("cb"), { " os dois   ", "ConflictHint" },
        key("c0"), { " nenhum", "ConflictHint" },
      },
      virt_text_pos = "eol",
    })
  end
  return list
end

local function block_at(buf, line)
  for _, b in ipairs(blocks(buf)) do
    if line >= b.start and line <= b.finish then return b end
  end
end

-- arquivo sem nenhum bloco: salva e marca como resolvido
local function maybe_mark_resolved(buf)
  if #blocks(buf) > 0 then return end
  local path = vim.api.nvim_buf_get_name(buf)
  local root = repo_root(path)
  if not root then return end
  local rel = path:sub(#root + 2)
  if not vim.tbl_contains(M.files(root), rel) then return end
  vim.api.nvim_buf_call(buf, function() vim.cmd("silent! write") end)
  local ok, out = git(root, { "add", "--", rel })
  if not ok then return notify("Não consegui marcar " .. rel .. " como resolvido:\n" .. out, vim.log.levels.WARN) end
  local left = #M.files(root)
  notify(rel .. " resolvido." .. (left > 0 and (" Faltam " .. left .. " arquivo" .. (left == 1 and "" or "s") .. ".") or " Todos os conflitos foram resolvidos."))
  M.refresh_window()
  if left == 0 and M.operation(root) then M.open(root) end
end

--- choice: "ours" | "theirs" | "both" | "none"
function M.resolve(choice, buf, line)
  buf = buf or vim.api.nvim_get_current_buf()
  line = line or vim.api.nvim_win_get_cursor(0)[1]
  local b = block_at(buf, line)
  if not b then return notify("O cursor não está num bloco em conflito. ]x vai para o próximo.") end
  local all = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local ours = vim.list_slice(all, b.start + 1, (b.base or b.mid) - 1)
  local theirs = vim.list_slice(all, b.mid + 1, b.finish - 1)
  local repl = choice == "ours" and ours or choice == "theirs" and theirs
    or choice == "both" and vim.list_extend(vim.list_extend({}, ours), theirs) or {}
  vim.api.nvim_buf_set_lines(buf, b.start - 1, b.finish, false, repl)
  pcall(vim.api.nvim_win_set_cursor, 0, { math.min(b.start, vim.api.nvim_buf_line_count(buf)), 0 })
  render(buf)
  maybe_mark_resolved(buf)
end

function M.jump(dir)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local list = blocks(0)
  if #list == 0 then return notify("Nenhum conflito neste arquivo.") end
  local target
  if dir > 0 then
    for _, b in ipairs(list) do if b.start > line then target = b; break end end
    target = target or list[1]
  else
    for i = #list, 1, -1 do if list[i].start < line then target = list[i]; break end end
    target = target or list[#list]
  end
  vim.api.nvim_win_set_cursor(0, { target.start, 0 })
  vim.cmd("normal! zz")
end

-- Alt+Enter dentro de um bloco: menu de resolução; fora dele, as ações de código de sempre
local function intention()
  local buf = vim.api.nvim_get_current_buf()
  local b = block_at(buf, vim.api.nvim_win_get_cursor(0)[1])
  if not b then return vim.lsp.buf.code_action() end
  require("config.popup_menu").open({
    { label = "Usar " .. short(b.ours, "o de cima"), key = "o", run = function() M.resolve("ours", buf, b.start) end },
    { label = "Usar " .. short(b.theirs, "o de baixo"), key = "t", run = function() M.resolve("theirs", buf, b.start) end },
    { label = "Usar os dois", key = "b", run = function() M.resolve("both", buf, b.start) end },
    { label = "Nenhum dos dois", key = "0", run = function() M.resolve("none", buf, b.start) end },
  }, { title = "Conflito", width = 40 })
end

local KEYS = {
  { "co", function() M.resolve("ours") end, "Conflito: usar o lado de cima" },
  { "ct", function() M.resolve("theirs") end, "Conflito: usar o lado de baixo" },
  { "cb", function() M.resolve("both") end, "Conflito: usar os dois" },
  { "c0", function() M.resolve("none") end, "Conflito: nenhum dos dois" },
  { "]x", function() M.jump(1) end, "Próximo conflito" },
  { "[x", function() M.jump(-1) end, "Conflito anterior" },
  { "<M-CR>", intention, "Resolver conflito / ações de código" },
}

-- liga as cores e os atalhos só enquanto o arquivo tem conflitos
local function attach(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then return end
  local has = #render(buf) > 0
  if has and not vim.b[buf].conflict_keys then
    for _, k in ipairs(KEYS) do vim.keymap.set("n", k[1], k[2], { buffer = buf, desc = k[3], nowait = true }) end
    vim.b[buf].conflict_keys = true
  elseif not has and vim.b[buf].conflict_keys then
    for _, k in ipairs(KEYS) do pcall(vim.keymap.del, "n", k[1], { buffer = buf }) end
    vim.b[buf].conflict_keys = false
  end
end
M.attach = attach

vim.api.nvim_create_autocmd({ "BufReadPost", "BufEnter", "TextChanged", "InsertLeave", "FileChangedShellPost" }, {
  group = vim.api.nvim_create_augroup("git_conflicts", { clear = true }),
  callback = function(ev) attach(ev.buf) end,
})

-- ---------------------------------------------------------------------------
-- Janela de conflitos
-- ---------------------------------------------------------------------------
local win = {}

local function count_markers(path)
  local f = io.open(path, "r")
  if not f then return 0 end
  local n = 0
  for l in f:lines() do if l:match("^<<<<<<<") then n = n + 1 end end
  f:close()
  return n
end

local function reload_buffers()
  vim.cmd("silent! checktime")
  for _, b in ipairs(vim.api.nvim_list_bufs()) do if vim.api.nvim_buf_is_loaded(b) then attach(b) end end
  pcall(function() require("neo-tree.sources.manager").refresh("filesystem") end)
  pcall(function() if require("config.commit").is_open() then require("config.commit").refresh() end end)
  vim.cmd("redrawstatus!")
end

local function draw()
  if not (win.buf and vim.api.nvim_buf_is_valid(win.buf)) then return end
  local root = win.root
  local op = M.operation(root)
  win.list = M.files(root)
  local text, marks = {}, {}
  local function add(s, hl) table.insert(text, s); if hl then table.insert(marks, { #text - 1, hl }) end end
  add("")
  if #win.list == 0 then
    add("  " .. I.ok .. "  Nenhum arquivo em conflito.", "ConflictWinOk")
    if op then add("  c continua o " .. OP_LABEL[op]:lower() .. ".", "ConflictWinDim") end
  else
    for _, rel in ipairs(win.list) do
      local n = count_markers(root .. "/" .. rel)
      local right = n > 0 and (n .. " conflito" .. (n == 1 and "" or "s")) or "sem marcadores"
      local left = "  " .. I.warn .. "  " .. rel
      local width = vim.api.nvim_win_get_width(win.id)
      add(left .. string.rep(" ", math.max(2, width - vim.fn.strdisplaywidth(left) - #right - 2)) .. right)
    end
  end
  add("")
  vim.bo[win.buf].modifiable = true
  vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, text)
  vim.bo[win.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(win.buf, ns, 0, -1)
  for _, m in ipairs(marks) do vim.api.nvim_buf_set_extmark(win.buf, ns, m[1], 0, { line_hl_group = m[2] }) end
  for i = 2, #win.list + 1 do
    if #win.list > 0 then vim.api.nvim_buf_set_extmark(win.buf, ns, i - 1, 2, { end_col = 2 + #I.warn, hl_group = "ConflictWinWarn" }) end
  end
  local title = op and (OP_LABEL[op] .. " em andamento") or "Conflitos"
  vim.api.nvim_win_set_config(win.id, { title = " " .. title .. " ", title_pos = "left",
    footer = " ⏎ abrir  o/t usar um lado no arquivo  a resolvido  c continuar  x abortar  q fechar ", footer_pos = "center" })
  if #win.list > 0 then pcall(vim.api.nvim_win_set_cursor, win.id, { 2, 0 }) end
end

function M.refresh_window() if win.id and vim.api.nvim_win_is_valid(win.id) then draw() end end

local function close()
  if win.id and vim.api.nvim_win_is_valid(win.id) then vim.api.nvim_win_close(win.id, true) end
  win = {}
end

local function selected()
  local line = vim.api.nvim_win_get_cursor(win.id)[1]
  return win.list[line - 1]
end

local function open_file(rel)
  local root = win.root
  close()
  local main = require("config.panels").main_win()
  if main then vim.api.nvim_set_current_win(main) end
  vim.cmd("edit " .. vim.fn.fnameescape(root .. "/" .. rel))
  local list = blocks(0)
  if list[1] then vim.api.nvim_win_set_cursor(0, { list[1].start, 0 }); vim.cmd("normal! zz") end
end

local function whole_file(side)
  local rel = selected()
  if not rel then return end
  local ok, out = git(win.root, { "checkout", "--" .. side, "--", rel })
  if ok then ok, out = git(win.root, { "add", "--", rel }) end
  if not ok then return notify("Não deu para usar esse lado em " .. rel .. ":\n" .. out, vim.log.levels.WARN) end
  notify(rel .. ": usada a versão " .. (side == "ours" and "de cima (HEAD)" or "de baixo") .. " no arquivo inteiro.")
  reload_buffers()
  draw()
end

local function mark_resolved()
  local rel = selected()
  if not rel then return end
  if count_markers(win.root .. "/" .. rel) > 0 and vim.fn.confirm(rel .. " ainda tem marcadores de conflito (<<<<<<<).\nMarcar como resolvido mesmo assim?", "&Marcar\n&Cancelar", 2, "Warning") ~= 1 then return end
  local ok, out = git(win.root, { "add", "--", rel })
  if not ok then return notify(out, vim.log.levels.WARN) end
  reload_buffers()
  draw()
end

local function continue()
  local op = M.operation(win.root)
  if not op then return notify("Não há merge, rebase, cherry-pick ou revert em andamento.") end
  if #M.files(win.root) > 0 then return notify("Ainda há arquivos em conflito. Resolva todos antes de continuar.", vim.log.levels.WARN) end
  -- core.editor=true: usa a mensagem de commit que o git já preparou, sem abrir editor
  local ok, out = git(win.root, { "-c", "core.editor=true", op, "--continue" })
  reload_buffers()
  if #M.files(win.root) > 0 then
    notify(OP_LABEL[op] .. " parou em outro conflito.", vim.log.levels.WARN)
    return draw()
  end
  if not ok and M.operation(win.root) then return notify(OP_LABEL[op] .. " não continuou:\n" .. out, vim.log.levels.WARN) end
  notify(OP_LABEL[op] .. " concluído.")
  close()
end

local function abort()
  local op = M.operation(win.root)
  if not op then return notify("Não há merge, rebase, cherry-pick ou revert em andamento.") end
  if vim.fn.confirm("Abortar o " .. OP_LABEL[op]:lower() .. "?\nOs arquivos voltam ao estado de antes, e o que você já resolveu se perde.", "&Abortar\n&Cancelar", 2, "Warning") ~= 1 then return end
  local ok, out = git(win.root, { op, "--abort" })
  reload_buffers()
  if not ok then return notify("Não consegui abortar:\n" .. out, vim.log.levels.WARN) end
  notify(OP_LABEL[op] .. " abortado.")
  close()
end

function M.open(root)
  root = root or repo_root(vim.api.nvim_buf_get_name(0)) or repo_root()
  if not root then return notify("Esta pasta não é um repositório git", vim.log.levels.WARN) end
  if win.id and vim.api.nvim_win_is_valid(win.id) then
    win.root = root
    vim.api.nvim_set_current_win(win.id)
    return draw()
  end
  local n = #M.files(root)
  local width = math.min(84, vim.o.columns - 8)
  local height = math.min(math.max(n, 1) + 2, math.floor(vim.o.lines * 0.5))
  win = { root = root, buf = vim.api.nvim_create_buf(false, true) }
  vim.bo[win.buf].bufhidden = "wipe"
  vim.bo[win.buf].filetype = "git_conflicts"
  win.id = vim.api.nvim_open_win(win.buf, true, {
    relative = "editor", width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2) - 2, col = math.floor((vim.o.columns - width) / 2),
    style = "minimal", border = "rounded", zindex = 60,
  })
  vim.wo[win.id].cursorline = true
  vim.wo[win.id].winhighlight = "Normal:NormalFloat,CursorLine:PmenuSel,FloatTitle:Title,FloatFooter:ConflictWinDim"
  local function map(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = win.buf, nowait = true }) end
  map("<CR>", function() local rel = selected(); if rel then open_file(rel) end end)
  map("<2-LeftMouse>", function() local rel = selected(); if rel then open_file(rel) end end)
  map("o", function() whole_file("ours") end)
  map("t", function() whole_file("theirs") end)
  map("a", mark_resolved)
  map("c", continue)
  map("x", abort)
  map("q", close)
  map("<Esc>", close)
  vim.api.nvim_create_autocmd("WinLeave", { buffer = win.buf, once = true, callback = function() vim.schedule(close) end })
  draw()
end

--- Depois de um merge/rebase/cherry-pick/revert: se parou em conflito, abre a janela
function M.check(root)
  root = root or repo_root()
  if root and #M.files(root) > 0 then
    reload_buffers()
    M.open(root)
    return true
  end
  return false
end

-- Ao abrir o Neovim (ou voltar para ele) com conflitos pendentes: avisa uma vez
local warned = false
vim.api.nvim_create_autocmd({ "VimEnter", "FocusGained" }, {
  group = vim.api.nvim_create_augroup("git_conflicts_warn", { clear = true }),
  callback = function()
    vim.defer_fn(function()
      local root = repo_root()
      if not root then return end
      local n = #M.files(root)
      if n == 0 then warned = false; return end
      if warned then return end
      warned = true
      notify(n .. " arquivo" .. (n == 1 and "" or "s") .. " em conflito. <leader>gx abre a lista.", vim.log.levels.WARN)
    end, 300)
  end,
})

vim.api.nvim_create_user_command("Conflitos", function() M.open() end, { desc = "Arquivos em conflito" })

local function colors()
  local ok, c = pcall(require, "config.palette")
  if not ok then return end
  local set = vim.api.nvim_set_hl
  set(0, "ConflictOurs", { bg = "#20352A" })
  set(0, "ConflictTheirs", { bg = "#1F3047" })
  set(0, "ConflictBase", { bg = "#2A2A2E" })
  set(0, "ConflictMarker", { fg = c.fg_dim, bg = "#26282C", bold = true })
  set(0, "ConflictKey", { fg = "#DFE1E5", bg = c.border, bold = true })
  set(0, "ConflictHint", { fg = c.fg_dim })
  set(0, "ConflictHintOurs", { fg = c.add })
  set(0, "ConflictHintTheirs", { fg = c.accent })
  set(0, "ConflictWinWarn", { fg = c.warn })
  set(0, "ConflictWinOk", { fg = c.hint })
  set(0, "ConflictWinDim", { fg = c.fg_dim })
end
colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = colors })

return M
