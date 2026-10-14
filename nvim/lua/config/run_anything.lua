-- Run Anything (Cmd+Shift+X): roda um comando ou script do projeto
-- numa aba nova do painel de terminal. A lista junta:
--   Recentes · scripts do package.json · scripts do composer.json · artisan · Makefile
-- e o que for digitado também pode rodar direto como comando de shell.
local M = {}

local I = {
  run = "\u{F040A}", recent = "\u{F02DA}", npm = "\u{E71E}", composer = "\u{E783}",
  artisan = "\u{E73F}", make = "\u{F0AD}", shell = "\u{F489}",
}

local ns = vim.api.nvim_create_namespace("run_anything")
local st = {}

-- ---------------------------------------------------------------------------
-- Recentes (por projeto, guardados entre sessões)
-- ---------------------------------------------------------------------------
local history_file = vim.fn.stdpath("data") .. "/run_anything.json"

local function read_history()
  local f = io.open(history_file, "r")
  if not f then return {} end
  local ok, data = pcall(vim.json.decode, f:read("*a"))
  f:close()
  return ok and type(data) == "table" and data or {}
end

local function project() return vim.fn.getcwd() end

local function remember(cmd)
  local all = read_history()
  local list = { cmd }
  for _, c in ipairs(all[project()] or {}) do
    if c ~= cmd and #list < 12 then table.insert(list, c) end
  end
  all[project()] = list
  local f = io.open(history_file, "w")
  if f then f:write(vim.json.encode(all)); f:close() end
end

-- ---------------------------------------------------------------------------
-- Fontes do projeto
-- ---------------------------------------------------------------------------
local function read_json(name)
  local f = io.open(project() .. "/" .. name, "r")
  if not f then return nil end
  local ok, data = pcall(vim.json.decode, f:read("*a"))
  f:close()
  return ok and data or nil
end

local function exists(name) return vim.uv.fs_stat(project() .. "/" .. name) ~= nil end

-- npm, yarn, pnpm ou bun, conforme o lockfile do projeto
local function js_runner()
  if exists("pnpm-lock.yaml") then return "pnpm" end
  if exists("yarn.lock") then return "yarn" end
  if exists("bun.lockb") or exists("bun.lock") then return "bun run" end
  return "npm run"
end

local function sorted_keys(t)
  local keys = vim.tbl_keys(t or {})
  table.sort(keys)
  return keys
end

local function make_targets()
  local f = io.open(project() .. "/Makefile", "r")
  if not f then return {} end
  local out, seen = {}, {}
  for line in f:lines() do
    local t = line:match("^([%w][%w%-_%.]*):[^=]")  or line:match("^([%w][%w%-_%.]*):$")
    if t and not seen[t] then seen[t] = true; table.insert(out, t) end
  end
  f:close()
  return out
end

local ARTISAN_COMMON = {
  { "serve", "Servidor de desenvolvimento" },
  { "migrate", "Roda as migrations" },
  { "migrate:fresh --seed", "Recria o banco e roda os seeders" },
  { "migrate:rollback", "Desfaz o último lote de migrations" },
  { "db:seed", "Roda os seeders" },
  { "tinker", "Console interativo" },
  { "queue:work", "Processa a fila" },
  { "schedule:work", "Roda o agendador" },
  { "test", "Roda os testes" },
  { "route:list", "Lista as rotas" },
  { "optimize:clear", "Limpa todos os caches" },
}

-- Comandos do artisan: lidos uma vez por projeto, em segundo plano (o artisan demora um pouco)
local artisan_cache = {}
local function load_artisan()
  local root = project()
  if artisan_cache[root] or not exists("artisan") then return end
  artisan_cache[root] = { loading = true, list = {} }
  -- sem avisos de "Deprecated" (alguns projetos imprimem antes do JSON)
  local php = require("config.project_php").bin(root) or "php" -- o PHP do projeto (Herd)
  vim.system({ php, "-d", "error_reporting=0", "-d", "display_errors=0", "artisan", "list", "--format=json" }, { cwd = root, text = true }, function(r)
    local out = r.stdout or ""
    local ok, data = pcall(vim.json.decode, out:sub((out:find("{", 1, true) or 1)))
    local list = {}
    if ok and type(data) == "table" then
      for _, c in ipairs(data.commands or {}) do
        if not c.hidden and c.name and c.name ~= "_complete" and c.name ~= "completion" then
          table.insert(list, { name = c.name, desc = c.description })
        end
      end
    end
    if #list == 0 then
      -- o artisan não respondeu (ex.: versão do PHP diferente da do projeto): comandos mais usados
      for _, c in ipairs(ARTISAN_COMMON) do table.insert(list, { name = c[1], desc = c[2] }) end
    end
    artisan_cache[root] = { list = list }
    vim.schedule(function() if st.list_buf then M.render() end end)
  end)
end

local function sections()
  local out = {}
  local function add(label, items) if #items > 0 then table.insert(out, { label = label, items = items }) end end

  local recent = {}
  for _, c in ipairs(read_history()[project()] or {}) do
    table.insert(recent, { cmd = c, label = c, icon = I.recent, icon_hl = "RunAnythingIcon" })
  end
  add("Recentes", recent)

  local pkg = read_json("package.json")
  local npm = {}
  if pkg then
    local runner = js_runner()
    for _, name in ipairs(sorted_keys(pkg.scripts)) do
      table.insert(npm, { cmd = runner .. " " .. name, label = runner .. " " .. name, hint = pkg.scripts[name], icon = I.npm, icon_hl = "RunAnythingNpm" })
    end
  end
  add("package.json", npm)

  local composer = read_json("composer.json")
  local comp = {}
  if composer then
    for _, name in ipairs(sorted_keys(composer.scripts)) do
      if not name:match("^pre%-") and not name:match("^post%-") then
        table.insert(comp, { cmd = "composer run " .. name, label = "composer run " .. name, icon = I.composer, icon_hl = "RunAnythingComposer" })
      end
    end
  end
  add("composer.json", comp)

  local art = {}
  local cache = artisan_cache[project()]
  if cache then
    for _, c in ipairs(cache.list) do
      table.insert(art, { cmd = "php artisan " .. c.name, label = "php artisan " .. c.name, hint = c.desc, icon = I.artisan, icon_hl = "RunAnythingArtisan" })
    end
    if cache.loading then table.insert(art, { label = "Carregando comandos do artisan…", muted = true }) end
  end
  add("Artisan", art)

  local mk = {}
  for _, t in ipairs(make_targets()) do
    table.insert(mk, { cmd = "make " .. t, label = "make " .. t, icon = I.make, icon_hl = "RunAnythingIcon" })
  end
  add("Makefile", mk)
  return out
end

-- Todas as palavras digitadas precisam aparecer (em qualquer ordem) no comando ou na descrição
local function matches(it, words)
  if it.muted then return #words == 0 end
  local hay = (it.label .. " " .. (it.hint or "")):lower()
  for _, w in ipairs(words) do
    if not hay:find(w, 1, true) then return false end
  end
  return true
end

local function build(query)
  local words = vim.split(query:lower(), "%s+", { trimempty = true })
  local items = {}
  -- com busca, Recentes não repete o que já aparece nas outras seções
  local in_recent = {}
  for _, sec in ipairs(sections()) do
    local found = {}
    for _, it in ipairs(sec.items) do
      if matches(it, words) and not (#words > 0 and in_recent[it.cmd] and sec.label ~= "Recentes") then
        table.insert(found, it)
        if sec.label == "Recentes" then in_recent[it.cmd] = true end
      end
    end
    if #found > 0 then
      table.insert(items, { header = true, label = sec.label })
      vim.list_extend(items, found)
    end
  end
  if #words > 0 then
    -- por último, o próprio texto digitado como comando de shell
    -- (assim o Enter roda o script encontrado; sem nenhum, roda o que foi digitado)
    table.insert(items, { header = true, label = "Comando" })
    table.insert(items, { cmd = vim.trim(query), label = vim.trim(query), hint = "rodar como comando de shell", icon = I.shell, icon_hl = "RunAnythingIcon", typed = true })
  end
  return items
end

-- ---------------------------------------------------------------------------
-- Rodar
-- ---------------------------------------------------------------------------
function M.run(cmd)
  cmd = vim.trim(cmd or "")
  if cmd == "" then return end
  remember(cmd)
  -- cada comando tem a sua aba no painel Run; rodar de novo reinicia a mesma aba
  local run = require("config.run_panel")
  local i = run.find(cmd)
  if i then return run.rerun(i) end
  run.new({ name = cmd, cmd = { vim.o.shell, "-ic", cmd } })
end

-- ---------------------------------------------------------------------------
-- Popup
-- ---------------------------------------------------------------------------
local function close()
  for _, w in ipairs({ st.input_win, st.list_win }) do
    if w and vim.api.nvim_win_is_valid(w) then pcall(vim.api.nvim_win_close, w, true) end
  end
  if st.prev_win and vim.api.nvim_win_is_valid(st.prev_win) then pcall(vim.api.nvim_set_current_win, st.prev_win) end
  vim.cmd.stopinsert()
  st = {}
end

local function selectable(it) return it and not it.header and not it.muted end

function M.select(i, dir)
  if not st.items or #st.items == 0 then return end
  i = math.max(1, math.min(i, #st.items))
  local tries = 0
  while not selectable(st.items[i]) and tries < #st.items do
    i = i + (dir or 1)
    if i > #st.items then i = 1 elseif i < 1 then i = #st.items end
    tries = tries + 1
  end
  st.sel = i
  if st.list_win and vim.api.nvim_win_is_valid(st.list_win) then
    pcall(vim.api.nvim_win_set_cursor, st.list_win, { i, 0 })
  end
end

function M.render()
  if not (st.list_buf and vim.api.nvim_buf_is_valid(st.list_buf)) then return end
  local query = vim.api.nvim_buf_get_lines(st.input_buf, 0, 1, false)[1] or ""
  st.items = build(query)
  local width = st.width
  local text, marks = {}, {}
  for i, it in ipairs(st.items) do
    local line
    if it.header then
      -- nome da seção seguido de um fio até a borda
      local label = " " .. it.label .. " "
      line = label .. string.rep("\u{2500}", width - vim.fn.strdisplaywidth(label) - 1)
      table.insert(marks, { i - 1, 0, #label, "RunAnythingHeader" })
      table.insert(marks, { i - 1, #label, -1, "RunAnythingRule" })
    elseif it.muted then
      line = "   " .. it.label
      table.insert(marks, { i - 1, 0, -1, "RunAnythingHint" })
    else
      local left = "  " .. it.icon .. "  " .. it.label
      local hint = it.hint or ""
      local free = width - vim.fn.strdisplaywidth(left) - 3
      if vim.fn.strdisplaywidth(hint) > free then
        hint = free > 6 and (vim.fn.strcharpart(hint, 0, free - 1) .. "…") or ""
      end
      line = left .. string.rep(" ", math.max(1, width - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(hint) - 1)) .. hint
      table.insert(marks, { i - 1, 2, 2 + #it.icon, it.icon_hl })
      table.insert(marks, { i - 1, #left, -1, "RunAnythingHint" })
    end
    table.insert(text, line)
  end
  if #text == 0 then
    text = { "", "   Nenhum script encontrado. Digite um comando para rodar no terminal." }
    table.insert(marks, { 1, 0, -1, "RunAnythingHint" })
  end
  vim.bo[st.list_buf].modifiable = true
  vim.api.nvim_buf_set_lines(st.list_buf, 0, -1, false, text)
  vim.bo[st.list_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(st.list_buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    local len = #text[m[1] + 1]
    local e = m[3] == -1 and len or math.min(m[3], len)
    if m[2] < e then vim.api.nvim_buf_set_extmark(st.list_buf, ns, m[1], m[2], { end_col = e, hl_group = m[4] }) end
  end
  if vim.api.nvim_win_is_valid(st.list_win) then
    vim.api.nvim_win_set_height(st.list_win, math.max(1, math.min(#text, st.max_height)))
    M.select(st.sel or 1, 1)
  end
end

local function activate(i)
  local it = st.items and st.items[i or st.sel]
  if not selectable(it) then return end
  local cmd = it.cmd
  close()
  vim.defer_fn(function() M.run(cmd) end, 50)
end

function M.open()
  if st.input_win and vim.api.nvim_win_is_valid(st.input_win) then return close() end
  load_artisan()
  st = { prev_win = vim.api.nvim_get_current_win() }
  st.width = math.min(96, vim.o.columns - 8)
  st.max_height = math.max(8, math.floor(vim.o.lines * 0.55))
  local col = math.floor((vim.o.columns - st.width) / 2)
  local row = math.max(2, math.floor(vim.o.lines * 0.12))

  -- campo em cima, lista logo abaixo, as duas com a mesma moldura
  st.input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[st.input_buf].bufhidden = "wipe"
  vim.b[st.input_buf].completion = false -- sem a lista de completar código no campo de busca
  st.input_win = vim.api.nvim_open_win(st.input_buf, true, {
    relative = "editor", row = row, col = col, width = st.width, height = 1,
    style = "minimal", border = { "╭", "─", "╮", "│", "", "", "", "│" }, zindex = 210,
    title = { { " Run ", "RunAnythingTitle" } }, title_pos = "left",
  })
  vim.wo[st.input_win].winhighlight = "Normal:RunAnythingNormal,FloatBorder:RunAnythingBorder"

  st.list_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[st.list_buf].bufhidden = "wipe"
  st.list_win = vim.api.nvim_open_win(st.list_buf, false, {
    relative = "editor", row = row + 2, col = col, width = st.width, height = st.max_height,
    style = "minimal", border = { "├", "─", "┤", "│", "╯", "─", "╰", "│" }, zindex = 210,
  })
  vim.wo[st.list_win].cursorline = true
  vim.wo[st.list_win].winhighlight = "Normal:RunAnythingNormal,FloatBorder:RunAnythingBorder,CursorLine:RunAnythingSel"

  -- ▶ à esquerda, texto de ajuda e dica à direita
  local ibuf = st.input_buf
  vim.api.nvim_buf_set_extmark(ibuf, ns, 0, 0, {
    virt_text = { { " " .. I.run .. "  ", "RunAnythingRun" } }, virt_text_pos = "inline", right_gravity = false,
  })
  local ph = vim.api.nvim_create_namespace("run_anything_placeholder")
  local function placeholder()
    vim.api.nvim_buf_clear_namespace(ibuf, ph, 0, -1)
    local empty = (vim.api.nvim_buf_get_lines(ibuf, 0, 1, false)[1] or "") == ""
    if empty then
      vim.api.nvim_buf_set_extmark(ibuf, ph, 0, 0, { virt_text = { { "Run command or script", "RunAnythingHint" } }, virt_text_pos = "overlay" })
    end
    vim.api.nvim_buf_set_extmark(ibuf, ph, 0, 0, {
      virt_text = { { empty and "Digite um comando ou busque um script " or "Enter roda ", "RunAnythingHint" } }, virt_text_pos = "right_align",
    })
  end
  placeholder()
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = ibuf,
    callback = function() if st.input_buf then placeholder(); st.sel = 1; M.render() end end,
  })
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = ibuf,
    callback = function()
      vim.schedule(function()
        local w = vim.api.nvim_get_current_win()
        if st.list_win and w ~= st.list_win and w ~= st.input_win then close() end
      end)
    end,
  })

  local function imap(lhs, fn) vim.keymap.set({ "i", "n" }, lhs, fn, { buffer = ibuf, nowait = true }) end
  for _, k in ipairs({ "<Down>", "<C-n>", "<C-j>", "<Tab>" }) do imap(k, function() M.select((st.sel or 1) + 1, 1) end) end
  for _, k in ipairs({ "<Up>", "<C-p>", "<C-k>", "<S-Tab>" }) do imap(k, function() M.select((st.sel or 1) - 1, -1) end) end
  imap("<CR>", function() activate() end)
  imap("<Esc>", close)
  vim.keymap.set("n", "q", close, { buffer = ibuf })

  local lbuf = st.list_buf
  -- (arrastar não vira seleção; se a lista estiver em modo visual, o clique e Esc/q valem igual)
  vim.keymap.set({ "n", "x", "i" }, "<LeftDrag>", "<Nop>", { buffer = lbuf })
  for _, k in ipairs({ "<Esc>", "q" }) do vim.keymap.set("x", k, close, { buffer = lbuf }) end
  vim.keymap.set({ "n", "i", "x" }, "<LeftRelease>", function()
    if vim.fn.mode():match("[vV\22]") then vim.cmd("normal! \27") end
    local pos = vim.fn.getmousepos()
    if pos.winid == st.list_win then activate(pos.line) end
  end, { buffer = lbuf })
  for _, k in ipairs({ "<Esc>", "q" }) do vim.keymap.set("n", k, close, { buffer = lbuf }) end
  vim.keymap.set("n", "<CR>", function() activate(vim.api.nvim_win_get_cursor(0)[1]) end, { buffer = lbuf })

  st.sel = 1
  M.render()
  vim.cmd.startinsert()
end

-- Cores (as mesmas do popup de branches)
local function colors()
  local ok, c = pcall(require, "config.palette")
  if not ok then return end
  local set = vim.api.nvim_set_hl
  set(0, "RunAnythingNormal", { fg = c.fg, bg = c.bg_float })
  set(0, "RunAnythingBorder", { fg = c.border, bg = c.bg_float })
  set(0, "RunAnythingTitle", { fg = c.fg, bg = c.bg_float, bold = true })
  set(0, "RunAnythingSel", { bg = "#2E436E" })
  set(0, "RunAnythingHint", { fg = c.fg_faint })
  set(0, "RunAnythingHeader", { fg = c.fg_dim })
  set(0, "RunAnythingRule", { fg = c.border })
  set(0, "RunAnythingRun", { fg = c.hint })
  set(0, "RunAnythingIcon", { fg = c.fg_dim })
  set(0, "RunAnythingNpm", { fg = "#CB3837" })
  set(0, "RunAnythingComposer", { fg = "#C5A47E" })
  set(0, "RunAnythingArtisan", { fg = "#F05340" })
end
colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = colors })

return M
