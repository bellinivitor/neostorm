-- Janela de Commit no estilo PhpStorm:
--   lista de alterações com caixinhas (o que entra no commit), "Unversioned Files" à parte,
--   mensagem do commit, Amend, e os botões Commit / Commit and Push.
local M = {}

local ICON = {
  on = "\u{F0132}", off = "\u{F0131}",
  open = "\u{F0140}", closed = "\u{F0142}",
  commit = "\u{F0718}",
}

M.items = {}        -- { rel, orig, x, y, untracked }
M.checked = {}      -- rel -> bool (lembra a escolha entre atualizações)
M.collapsed = {}    -- grupo -> bool
M.amend = false
M.lines = {}        -- linha da lista -> { kind = "header"|"file", group, item }
M.win = {}          -- list / msg / act

local ns = vim.api.nvim_create_namespace("commit_panel")

-- Changelists (como no PhpStorm): listas nomeadas de arquivos alterados. A "ativa" recebe os
-- arquivos alterados daqui para a frente. Ficam em .git/neostorm-changelists.json (não vão
-- para o commit e sobrevivem ao fechar o Neovim).
local DEFAULT_CL = "Changes"
M.cl = { lists = { DEFAULT_CL }, active = DEFAULT_CL, files = {} }

local function cl_file()
  if not M.root then return nil end
  local r = vim.system({ "git", "rev-parse", "--absolute-git-dir" }, { cwd = M.root, text = true }):wait()
  local dir = vim.trim(r.stdout or "")
  return r.code == 0 and dir ~= "" and (dir .. "/neostorm-changelists.json") or nil
end

local function cl_load()
  M.cl = { lists = { DEFAULT_CL }, active = DEFAULT_CL, files = {} }
  local path = cl_file()
  local f = path and io.open(path, "r")
  if not f then return end
  local ok, data = pcall(vim.json.decode, f:read("*a"))
  f:close()
  if ok and type(data) == "table" and type(data.lists) == "table" and #data.lists > 0 then
    M.cl.lists, M.cl.files = data.lists, type(data.files) == "table" and data.files or {}
    M.cl.active = vim.tbl_contains(data.lists, data.active) and data.active or data.lists[1]
  end
end

local function cl_save()
  local path = cl_file()
  local f = path and io.open(path, "w")
  if f then f:write(vim.json.encode(M.cl)); f:close() end
end

-- ---------------------------------------------------------------------------
-- git
-- ---------------------------------------------------------------------------
local function root()
  local r = vim.system({ "git", "rev-parse", "--show-toplevel" }, { cwd = vim.fn.getcwd(), text = true }):wait()
  local dir = vim.trim(r.stdout or "")
  return r.code == 0 and dir ~= "" and dir or nil
end

local function git_async(args, cb)
  local cmd = { "git" }
  vim.list_extend(cmd, args)
  -- sem terminal para digitar senha: falha na hora (e oferecemos configurar a conta) em vez de travar
  vim.system(cmd, { cwd = M.root, text = true, env = { GIT_TERMINAL_PROMPT = "0" } },
    function(r) vim.schedule(function() cb(r) end) end)
end

local function load_status()
  M.root = root()
  M.items = {}
  if not M.root then return end
  local r = vim.system({ "git", "status", "--porcelain=v1", "-z", "--untracked-files=all" }, { cwd = M.root, text = true }):wait()
  local t = vim.split(r.stdout or "", "\0", { plain = true, trimempty = true })
  local i = 1
  while i <= #t do
    local x, y, rel = t[i]:sub(1, 1), t[i]:sub(2, 2), t[i]:sub(4)
    local item = { rel = rel, x = x, y = y, untracked = (x == "?") }
    if x == "R" or x == "C" then i = i + 1; item.orig = t[i] end
    if M.checked[rel] == nil then M.checked[rel] = not item.untracked end
    table.insert(M.items, item)
    i = i + 1
  end
  table.sort(M.items, function(a, b) return a.rel < b.rel end)
  -- changelists: arquivo novo na lista vai para a ativa; tira os que não estão mais alterados
  cl_load()
  local present, changed = {}, false
  for _, it in ipairs(M.items) do
    present[it.rel] = true
    local list = M.cl.files[it.rel]
    if list and not vim.tbl_contains(M.cl.lists, list) then M.cl.files[it.rel] = nil; list = nil; changed = true end
    if not list and not it.untracked then M.cl.files[it.rel] = M.cl.active; changed = true end
  end
  for rel in pairs(M.cl.files) do
    if not present[rel] then M.cl.files[rel] = nil; changed = true end
  end
  if changed then cl_save() end
end

local function status_of(item)
  if item.untracked then return "?", "CommitUntracked" end
  local s = (item.x ~= " " and item.x) or item.y
  if s == "A" then return "A", "CommitAdded" end
  if s == "D" then return "D", "CommitDeleted" end
  if s == "R" then return "R", "CommitModified" end
  return "M", "CommitModified"
end

-- ---------------------------------------------------------------------------
-- Desenho da lista
-- ---------------------------------------------------------------------------
local function groups()
  local out, by_name, unversioned = {}, {}, {}
  for _, name in ipairs(M.cl.lists) do
    local g = { id = "cl:" .. name, name = name, items = {}, changelist = true, active = name == M.cl.active }
    by_name[name] = g
    table.insert(out, g)
  end
  for _, it in ipairs(M.items) do
    local g = by_name[M.cl.files[it.rel] or ""]
    if g then table.insert(g.items, it) else table.insert(unversioned, it) end
  end
  table.insert(out, { id = "unversioned", name = "Unversioned Files", items = unversioned })
  return out
end

function M.render()
  local buf = M.list_buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
  local text, marks = {}, {}
  M.lines = {}
  local function add(line, hl_spans, meta)
    table.insert(text, line)
    M.lines[#text] = meta
    for _, s in ipairs(hl_spans or {}) do table.insert(marks, { #text - 1, s[1], s[2], s[3] }) end
  end

  if not M.root then
    add("  Não é um repositório git", { { 0, -1, "Comment" } }, nil)
  elseif #M.items == 0 then
    add("  Nenhuma alteração", { { 0, -1, "Comment" } }, nil)
  end

  for _, g in ipairs(groups()) do
    -- changelists aparecem mesmo vazias (como no PhpStorm); "Unversioned Files" só com arquivos
    if #g.items > 0 or (g.changelist and M.root and (#M.items > 0 or #M.cl.lists > 1)) then
      local all = #g.items > 0
      for _, it in ipairs(g.items) do if not M.checked[it.rel] then all = false end end
      local arrow = M.collapsed[g.id] and ICON.closed or ICON.open
      local box = all and ICON.on or ICON.off
      local count = #g.items == 0 and "vazia" or (#g.items == 1 and "1 file" or (#g.items .. " files"))
      if g.active and #M.cl.lists > 1 then count = count .. "  ativa" end
      local line = " " .. arrow .. " " .. box .. " " .. g.name .. "  " .. count
      local b1 = #(" " .. arrow .. " ")
      local b2 = b1 + #box
      local n1 = b2 + 1
      add(line, { { b1, b2, all and "CommitCheckOn" or "CommitCheckOff" }, { n1, n1 + #g.name, "CommitHeader" }, { n1 + #g.name, -1, "Comment" } },
        { kind = "header", group = g })
      if not M.collapsed[g.id] then
        for _, it in ipairs(g.items) do
          local letter, hl = status_of(it)
          local name = vim.fn.fnamemodify(it.rel, ":t")
          local dir = vim.fn.fnamemodify(it.rel, ":h")
          dir = dir == "." and "" or dir
          local on = M.checked[it.rel]
          local box2 = on and ICON.on or ICON.off
          local prefix = "     " .. box2 .. " "
          local l = prefix .. letter .. " " .. name .. "  " .. dir
          local p1 = #"     "
          local s1 = #prefix
          local nm = s1 + 2
          add(l, {
            { p1, p1 + #box2, on and "CommitCheckOn" or "CommitCheckOff" },
            { s1, s1 + 1, hl },
            { nm, nm + #name, hl },
            { nm + #name, -1, "Comment" },
          }, { kind = "file", item = it })
        end
      end
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    local line_len = #text[m[1] + 1]
    local e = m[3] == -1 and line_len or math.min(m[3], line_len)
    if m[2] < e then
      vim.api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = e, hl_group = m[4] })
    end
  end
  M.render_actions()
end

function M.refresh()
  load_status()
  M.render()
end

-- ---------------------------------------------------------------------------
-- Ações na lista
-- ---------------------------------------------------------------------------
local function line_meta(l) return M.lines[l or vim.api.nvim_win_get_cursor(0)[1]] end

function M.toggle_line(l)
  local meta = line_meta(l)
  if not meta then return end
  if meta.kind == "file" then
    M.checked[meta.item.rel] = not M.checked[meta.item.rel]
  else
    local all = true
    for _, it in ipairs(meta.group.items) do if not M.checked[it.rel] then all = false end end
    for _, it in ipairs(meta.group.items) do M.checked[it.rel] = not all end
  end
  M.render()
end

function M.toggle_collapse(l)
  local meta = line_meta(l)
  if meta and meta.kind == "header" then
    M.collapsed[meta.group.id] = not M.collapsed[meta.group.id]
    M.render()
  end
end

local function abs(item) return M.root .. "/" .. item.rel end

function M.diff_line(l)
  local meta = line_meta(l)
  if meta and meta.kind == "file" then require("config.git_rollback").diff(abs(meta.item)) end
end

-- Rollback de todos os arquivos de uma changelist, com uma confirmação só
function M.rollback_list(group)
  local items = group.items
  if #items == 0 then return vim.notify("A changelist '" .. group.name .. "' está vazia", vim.log.levels.INFO) end
  local new = vim.tbl_filter(function(it) return it.untracked or it.x == "A" end, items)
  local msg = "Desfazer as alterações de " .. (#items == 1 and "1 arquivo" or (#items .. " arquivos")) .. " da changelist '" .. group.name .. "'?"
  if #new > 0 then
    msg = msg .. "\n\n" .. (#new == 1 and "1 arquivo novo será APAGADO:" or (#new .. " arquivos novos serão APAGADOS:"))
    for k, it in ipairs(new) do
      if k > 5 then msg = msg .. "\n  ..." break end
      msg = msg .. "\n  " .. it.rel
    end
  end
  if vim.fn.confirm(msg, "&Rollback\n&Cancelar", 2, "Question") ~= 1 then return end
  local n = 0
  for _, it in ipairs(items) do
    n = n + (require("config.git_rollback").rollback(abs(it), { force = true, quiet = true }) or 0)
  end
  vim.notify(("Rollback feito: %d arquivo(s) de '%s'"):format(n, group.name), vim.log.levels.INFO)
  M.refresh()
end

function M.rollback_line(l)
  local meta = line_meta(l)
  if not meta then return end
  if meta.kind == "file" then
    require("config.git_rollback").rollback(abs(meta.item))
    return M.refresh()
  end
  -- cabeçalho: todos os arquivos da changelist
  if meta.group.changelist then return M.rollback_list(meta.group) end
end

-- ---------------------------------------------------------------------------
-- Changelists
-- ---------------------------------------------------------------------------
local function valid_name(name, except)
  name = vim.trim(name or "")
  if name == "" then return nil end
  if name ~= except and vim.tbl_contains(M.cl.lists, name) then
    vim.notify("Já existe uma changelist '" .. name .. "'", vim.log.levels.WARN)
    return nil
  end
  return name
end

--- Nova changelist; cb(nome) é chamado depois de criar (ex.: mover um arquivo para ela)
function M.new_changelist(cb)
  vim.ui.input({ prompt = "Nova changelist: " }, function(input)
    local name = valid_name(input)
    if not name then return end
    table.insert(M.cl.lists, name)
    cl_save()
    if cb then cb(name) end
    M.render()
  end)
end

function M.rename_changelist(group)
  vim.ui.input({ prompt = "Novo nome para '" .. group.name .. "': ", default = group.name }, function(input)
    local name = valid_name(input, group.name)
    if not name or name == group.name then return end
    for i, l in ipairs(M.cl.lists) do if l == group.name then M.cl.lists[i] = name end end
    for rel, l in pairs(M.cl.files) do if l == group.name then M.cl.files[rel] = name end end
    if M.cl.active == group.name then M.cl.active = name end
    cl_save()
    M.render()
  end)
end

function M.set_active(group)
  M.cl.active = group.name
  cl_save()
  vim.notify("Changelist ativa: " .. group.name, vim.log.levels.INFO)
  M.render()
end

-- Apaga a changelist; os arquivos dela vão para a ativa
function M.delete_changelist(group)
  if group.name == M.cl.active then return vim.notify("Não dá para apagar a changelist ativa", vim.log.levels.WARN) end
  if #group.items > 0 and vim.fn.confirm("Apagar a changelist '" .. group.name .. "'?\nOs " .. #group.items
    .. " arquivo(s) dela vão para '" .. M.cl.active .. "' (as alterações continuam).", "&Apagar\n&Cancelar", 2, "Question") ~= 1 then return end
  M.cl.lists = vim.tbl_filter(function(l) return l ~= group.name end, M.cl.lists)
  for rel, l in pairs(M.cl.files) do if l == group.name then M.cl.files[rel] = M.cl.active end end
  cl_save()
  M.render()
end

--- Move o arquivo da linha para outra changelist (ou uma nova)
function M.move_line(l)
  local meta = line_meta(l)
  if not (meta and meta.kind == "file") then return vim.notify("Escolha um arquivo para mover", vim.log.levels.INFO) end
  local rel = meta.item.rel
  local current = M.cl.files[rel]
  local NEW = "\u{F0415}  Nova changelist…"
  local options = vim.tbl_filter(function(name) return name ~= current end, M.cl.lists)
  table.insert(options, NEW)
  local function move(name)
    M.cl.files[rel] = name
    cl_save()
    M.render()
  end
  vim.ui.select(options, { prompt = "Mover " .. vim.fn.fnamemodify(rel, ":t") .. " para" }, function(choice)
    if not choice then return end
    if choice == NEW then return vim.defer_fn(function() M.new_changelist(move) end, 50) end
    move(choice)
  end)
end

-- Menu do botão direito numa linha da lista
function M.menu(l)
  local meta = line_meta(l)
  if not meta then return end
  local items = {}
  if meta.kind == "file" then
    table.insert(items, { label = "\u{F0EC6}  Ver diff", key = "d", run = function() M.diff_line(l) end })
    table.insert(items, { label = "\u{F0453}  Mover para outra changelist…", key = "m", run = function() M.move_line(l) end })
    table.insert(items, { label = "\u{F054C}  Rollback", key = "r", hint = "⌥⌘Z", run = function() M.rollback_line(l) end })
  elseif meta.group.changelist then
    local g = meta.group
    if #g.items > 0 then
      table.insert(items, { label = "\u{F054C}  Rollback", key = "r", hint = "⌥⌘Z", run = function() M.rollback_list(g) end })
    end
    table.insert(items, { label = "\u{F0415}  Nova changelist…", key = "n", run = function() M.new_changelist() end })
    table.insert(items, { label = "\u{F03EB}  Renomear…", key = "e", run = function() M.rename_changelist(g) end })
    if not g.active then
      table.insert(items, { label = "\u{F012C}  Definir como ativa", key = "a", run = function() M.set_active(g) end })
      table.insert(items, { label = "\u{F01B4}  Apagar changelist", key = "x", run = function() M.delete_changelist(g) end })
    end
  else
    table.insert(items, { label = "\u{F0415}  Nova changelist…", key = "n", run = function() M.new_changelist() end })
  end
  require("config.popup_menu").open(items, { mouse = true, width = 34 })
end

-- ---------------------------------------------------------------------------
-- Mensagem, Amend e botões
-- ---------------------------------------------------------------------------
function M.message()
  local lines = vim.api.nvim_buf_get_lines(M.msg_buf, 0, -1, false)
  local out = {}
  for _, l in ipairs(lines) do if not l:match("^#") then table.insert(out, l) end end
  return vim.trim(table.concat(out, "\n"))
end

local function set_message(text)
  vim.api.nvim_buf_set_lines(M.msg_buf, 0, -1, false, vim.split(text or "", "\n", { plain = true }))
end

function M.toggle_amend()
  M.amend = not M.amend
  if M.amend and M.message() == "" then
    local r = vim.system({ "git", "log", "-1", "--format=%B" }, { cwd = M.root, text = true }):wait()
    M.amend_msg = vim.trim(r.stdout or "")
    set_message(M.amend_msg)
  elseif not M.amend and M.amend_msg and M.message() == M.amend_msg then
    set_message("")
  end
  vim.cmd("redrawstatus!")
end
function _G.CommitToggleAmend() vim.schedule(M.toggle_amend) end

function M.msg_winbar()
  local box = M.amend and ICON.on or ICON.off
  return "%#CommitBar#%@v:lua.CommitToggleAmend@ " .. box .. " Amend %X%#Comment# último commit%*"
end

M.buttons = {}
function M.render_actions()
  local buf = M.act_buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
  local n = 0
  for _, it in ipairs(M.items) do if M.checked[it.rel] then n = n + 1 end end
  local b1 = "  Commit  "
  local b2 = "  Commit and Push…  "
  local info = n == 1 and "1 arquivo" or (n .. " arquivos")
  local line = " " .. b1 .. " " .. b2 .. "  " .. info .. "  \u{2318}\u{23CE}"
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local s1 = 1
  local s2 = s1 + #b1 + 1
  vim.api.nvim_buf_set_extmark(buf, ns, 0, s1, { end_col = s1 + #b1, hl_group = "CommitButtonPrimary" })
  vim.api.nvim_buf_set_extmark(buf, ns, 0, s2, { end_col = s2 + #b2, hl_group = "CommitButton" })
  vim.api.nvim_buf_set_extmark(buf, ns, 0, s2 + #b2, { end_col = #line, hl_group = "Comment" })
  -- colunas (em células) de cada botão para o clique
  M.buttons = {
    { from = vim.fn.strdisplaywidth(line:sub(1, s1)) + 1, to = vim.fn.strdisplaywidth(line:sub(1, s1 + #b1)), push = false },
    { from = vim.fn.strdisplaywidth(line:sub(1, s2)) + 1, to = vim.fn.strdisplaywidth(line:sub(1, s2 + #b2)), push = true },
  }
end

-- ---------------------------------------------------------------------------
-- Commit / Push
-- ---------------------------------------------------------------------------
local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "Commit" }) end

function M.push()
  notify("Enviando (push)…")
  local function failed(r)
    -- sem credencial para o servidor: oferece configurar a conta (Contas do Git)
    if require("config.git_accounts").handle_auth_error(r.stderr, M.root) then return end
    notify("Push falhou:\n" .. (r.stderr or ""), vim.log.levels.ERROR)
  end
  git_async({ "push" }, function(r)
    if r.code ~= 0 and (r.stderr or ""):match("no upstream") then
      return git_async({ "push", "-u", "origin", "HEAD" }, function(r2)
        if r2.code == 0 then notify("Push feito") else failed(r2) end
      end)
    end
    if r.code == 0 then notify("Push feito") else failed(r) end
  end)
end

local function after_commit(r, push)
  if r.code ~= 0 then
    return notify("Commit falhou:\n" .. vim.trim((r.stderr or "") .. "\n" .. (r.stdout or "")), vim.log.levels.ERROR)
  end
  local first = vim.split(vim.trim(r.stdout or ""), "\n")[1] or ""
  notify("Commit feito: " .. first)
  set_message("")
  M.amend, M.amend_msg = false, nil
  M.refresh()
  vim.cmd("silent! checktime")
  pcall(function() require("neo-tree.sources.manager").refresh("filesystem") end)
  if push then M.push() end
end

function M.commit(push)
  if not M.root then return notify("Não é um repositório git", vim.log.levels.WARN) end
  local msg = M.message()
  if msg == "" then return notify("Escreva a mensagem do commit", vim.log.levels.WARN) end
  local paths, to_add = {}, {}
  for _, it in ipairs(M.items) do
    if M.checked[it.rel] then
      table.insert(paths, it.rel)
      if it.orig then table.insert(paths, it.orig) end
      -- exclusão já registrada (D na primeira coluna) não precisa de git add
      if it.x ~= "D" then table.insert(to_add, it.rel) end
    end
  end
  if #paths == 0 and not M.amend then return notify("Marque ao menos um arquivo", vim.log.levels.WARN) end

  local function do_commit()
    local args = { "commit", "-m", msg }
    if M.amend then table.insert(args, "--amend") end
    if #paths > 0 then
      table.insert(args, "--")
      vim.list_extend(args, paths)
    else
      table.insert(args, "--only")
    end
    git_async(args, function(r) after_commit(r, push) end)
  end

  if #to_add > 0 then
    local add = { "add", "-A", "--" }
    vim.list_extend(add, to_add)
    git_async(add, function(r)
      if r.code ~= 0 then return notify("git add falhou:\n" .. (r.stderr or ""), vim.log.levels.ERROR) end
      do_commit()
    end)
  else
    do_commit()
  end
end

-- ---------------------------------------------------------------------------
-- Janelas
-- ---------------------------------------------------------------------------
local function scratch(name, ft)
  local b = vim.api.nvim_create_buf(false, true)
  vim.bo[b].bufhidden = "hide"
  vim.bo[b].swapfile = false
  vim.bo[b].filetype = ft
  pcall(vim.api.nvim_buf_set_name, b, name)
  return b
end

local function ensure_buffers()
  if not (M.list_buf and vim.api.nvim_buf_is_valid(M.list_buf)) then
    M.list_buf = scratch("Commit://changes", "commit_list")
    local b = M.list_buf
    local function map(lhs, fn, desc) vim.keymap.set("n", lhs, fn, { buffer = b, nowait = true, desc = desc }) end
    map("<Space>", function() M.toggle_line() end, "Marcar/desmarcar")
    map("x", function() M.toggle_line() end, "Marcar/desmarcar")
    map("<CR>", function()
      local meta = line_meta()
      if meta and meta.kind == "header" then M.toggle_collapse() else M.diff_line() end
    end, "Abrir diff / expandir grupo")
    map("<Tab>", function() M.toggle_collapse() end, "Expandir/recolher grupo")
    map("D", function() M.diff_line() end, "Ver diff")
    -- F4 / o / Cmd+↓: abre o arquivo no editor (como Jump to Source do PhpStorm)
    local function open_file()
      local meta = line_meta()
      if not (meta and meta.kind == "file") then return end
      local p = abs(meta.item)
      -- janela de código (o dashboard conta); se não houver nenhuma, abre uma à esquerda do painel
      local main = require("config.panels").main_win()
      if main then
        vim.api.nvim_set_current_win(main)
      else
        vim.api.nvim_open_win(0, true, { split = "left", win = M.win.list })
      end
      vim.cmd("edit " .. vim.fn.fnameescape(p))
    end
    map("<F4>", open_file, "Abrir arquivo")
    map("o", open_file, "Abrir arquivo")
    map("<D-Down>", open_file, "Abrir arquivo") -- Cmd+↓ (Jump to Source do PhpStorm)
    map("<D-M-z>", function() M.rollback_line() end, "Rollback")
    map("gr", function() M.rollback_line() end, "Rollback")
    map("r", function() M.refresh() end, "Atualizar")
    map("n", function() M.new_changelist() end, "Nova changelist")
    map("m", function() M.move_line() end, "Mover para outra changelist")
    map("q", function() M.close() end, "Fechar")
    map("<D-CR>", function() M.commit(false) end, "Commit")
    map("i", function() M.focus_message() end, "Escrever mensagem")
    -- Mouse: clique na caixinha marca/desmarca; na seta recolhe; duplo clique abre o diff
    map("<LeftRelease>", function()
      local pos = vim.fn.getmousepos()
      if pos.winid ~= M.win.list then return end
      local meta = M.lines[pos.line]
      if not meta then return end
      local col = pos.column
      if meta.kind == "header" then
        if col <= 3 then M.toggle_collapse(pos.line) elseif col <= 6 then M.toggle_line(pos.line) end
      elseif col >= 5 and col <= 8 then
        M.toggle_line(pos.line)
      end
    end)
    map("<2-LeftMouse>", function()
      local pos = vim.fn.getmousepos()
      local meta = M.lines[pos.line]
      -- (abre depois que o duplo clique termina; senão o diff entrava em modo visual)
      if meta and meta.kind == "file" then require("config.panels").after_click(M.diff_line)(pos.line) end
    end)
  end
  if not (M.msg_buf and vim.api.nvim_buf_is_valid(M.msg_buf)) then
    M.msg_buf = scratch("Commit://message", "gitcommit")
    vim.bo[M.msg_buf].buftype = "nofile"
    for _, mode in ipairs({ "n", "i" }) do
      vim.keymap.set(mode, "<D-CR>", function() vim.cmd.stopinsert(); M.commit(false) end, { buffer = M.msg_buf, desc = "Commit" })
      vim.keymap.set(mode, "<D-S-CR>", function() vim.cmd.stopinsert(); M.commit(true) end, { buffer = M.msg_buf, desc = "Commit and Push" })
    end
    -- Texto de exemplo enquanto a mensagem estiver vazia
    local function placeholder()
      vim.api.nvim_buf_clear_namespace(M.msg_buf, ns, 0, -1)
      if M.message() == "" then
        vim.api.nvim_buf_set_extmark(M.msg_buf, ns, 0, 0, { virt_text = { { "Mensagem do commit", "Comment" } }, virt_text_pos = "overlay" })
      end
    end
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufEnter" }, { buffer = M.msg_buf, callback = placeholder })
    placeholder()
  end
  if not (M.act_buf and vim.api.nvim_buf_is_valid(M.act_buf)) then
    M.act_buf = scratch("Commit://actions", "commit_actions")
    vim.keymap.set("n", "<LeftRelease>", function()
      local pos = vim.fn.getmousepos()
      if pos.winid ~= M.win.act then return end
      for _, btn in ipairs(M.buttons) do
        if pos.column >= btn.from and pos.column <= btn.to then return M.commit(btn.push) end
      end
    end, { buffer = M.act_buf })
  end
end

local function valid(w) return w and vim.api.nvim_win_is_valid(w) end
function M.is_open() return valid(M.win.list) end

-- Cmd+W em qualquer parte do painel fecha o painel (e não o conteúdo dele)
local function close_keys()
  for _, b in ipairs({ M.list_buf, M.msg_buf, M.act_buf }) do
    if b and vim.api.nvim_buf_is_valid(b) then
      vim.keymap.set("n", "<D-w>", function() M.close() end, { buffer = b, desc = "Fechar Commit" })
    end
  end
end

local function style(win, opts)
  local wo = vim.wo[win]
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "no"
  wo.statuscolumn = ""
  wo.foldcolumn = "0"
  wo.winfixwidth = true
  wo.wrap = opts.wrap or false
  wo.cursorline = opts.cursorline or false
  wo.winhighlight = "Normal:CommitPanel,NormalNC:CommitPanel,CursorLine:CommitCursorLine,WinBar:CommitBar,WinBarNC:CommitBar,EndOfBuffer:CommitPanel"
  if opts.winbar then wo.winbar = opts.winbar end
end

function M.open(opts)
  opts = opts or {}
  ensure_buffers()
  close_keys()
  load_status()
  if not M.is_open() then
    -- mesmo lugar do painel de projeto e do Structure: fecha eles
    pcall(function() require("config.activity_bar").close_slot("commit") end)
    local width = 46
    M.win.list = vim.api.nvim_open_win(M.list_buf, true, { split = "right", win = -1, width = width })
    style(M.win.list, { cursorline = true, winbar = "%#CommitTitle# " .. ICON.commit .. " Commit %*" })
    M.win.msg = vim.api.nvim_open_win(M.msg_buf, false, { split = "below", win = M.win.list, height = 9 })
    style(M.win.msg, { wrap = true, winbar = "%!v:lua.require'config.commit'.msg_winbar()" })
    M.win.act = vim.api.nvim_open_win(M.act_buf, false, { split = "below", win = M.win.msg, height = 1 })
    style(M.win.act, {})
    vim.wo[M.win.act].winfixheight = true
    vim.wo[M.win.msg].winfixheight = true
    local panels = require("config.panels")
    panels.mark(M.win.list, M.list_buf)
    panels.mark(M.win.msg, M.msg_buf)
    panels.mark(M.win.act, M.act_buf)
  end
  M.render()
  if opts.focus_message then M.focus_message() else vim.api.nvim_set_current_win(M.win.list) end
  pcall(function() require("config.activity_bar").ensure() end)
end

function M.focus_message()
  if not valid(M.win.msg) then return M.open({ focus_message = true }) end
  vim.api.nvim_set_current_win(M.win.msg)
  if M.message() == "" then vim.cmd.startinsert() end
end

function M.close()
  for _, k in ipairs({ "act", "msg", "list" }) do
    if valid(M.win[k]) then pcall(vim.api.nvim_win_close, M.win[k], true) end
    M.win[k] = nil
  end
end

function M.toggle(opts)
  if M.is_open() then return M.close() end
  M.open(opts)
end

-- Atualiza a lista quando salvar arquivos ou voltar para o editor
vim.api.nvim_create_autocmd({ "BufWritePost", "FocusGained" }, {
  callback = function() if M.is_open() then vim.schedule(M.refresh) end end,
})
-- Se uma das janelas do painel for fechada por fora, fecha as outras
vim.api.nvim_create_autocmd("WinClosed", {
  callback = function(ev)
    local w = tonumber(ev.match)
    if w == M.win.list or w == M.win.msg then vim.schedule(M.close) end
  end,
})

-- Cores
local function colors()
  local ok, c = pcall(require, "config.palette")
  if not ok then return end
  local set = vim.api.nvim_set_hl
  set(0, "CommitPanel", { fg = c.fg, bg = c.bg_alt })
  set(0, "CommitCursorLine", { bg = require("config.palette").sel_row })
  set(0, "CommitBar", { fg = c.fg, bg = c.bg_alt })
  set(0, "CommitTitle", { fg = c.fg, bg = c.bg_alt, bold = true })
  set(0, "CommitHeader", { fg = c.fg, bold = true })
  set(0, "CommitCheckOn", { fg = c.accent })
  set(0, "CommitCheckOff", { fg = c.fg_faint })
  set(0, "CommitModified", { fg = c.git_modified })
  set(0, "CommitAdded", { fg = c.git_added })
  set(0, "CommitDeleted", { fg = c.fg_faint })
  set(0, "CommitUntracked", { fg = c.git_untracked })
  set(0, "CommitButtonPrimary", { fg = c.primary_fg, bg = c.primary, bold = true })
  set(0, "CommitButton", { fg = c.fg, bg = c.border })
end
colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = colors })

return M
