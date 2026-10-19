-- Recent Locations (Cmd+Shift+E no PhpStorm): os últimos pontos do código por onde você
-- passou, com o trecho de código de cada um. Diferente dos arquivos recentes (Cmd+E):
-- aqui é o lugar exato (arquivo + linha). Guardado por projeto, sobrevive ao fechar.
--   ShipmentController.php:38   public function show(Shipment $shipment)   app/Http/Controllers
local M = {}

local MAX = 60
local NEAR = 8 -- pontos a até 8 linhas no mesmo arquivo viram um só
local FILE = vim.fn.stdpath("data") .. "/recent_locations.json"
local ns = vim.api.nvim_create_namespace("recent_locations")

local all -- { [projeto] = { { file, line, col, text }, ... } } (mais recente primeiro)
local st = {}

local function load()
  if all then return all end
  local f = io.open(FILE, "r")
  all = {}
  if f then
    local ok, data = pcall(vim.json.decode, f:read("*a"))
    f:close()
    if ok and type(data) == "table" then all = data end
  end
  return all
end

local function save()
  local f = io.open(FILE, "w")
  if f then f:write(vim.json.encode(all)); f:close() end
end

local function project() return vim.fn.getcwd() end

-- Registra a posição atual (só arquivos de verdade, dentro do projeto)
function M.record()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "" or vim.api.nvim_win_get_config(0).relative ~= "" then return end
  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" or not vim.uv.fs_stat(file) then return end
  local root = project()
  if file:sub(1, #root + 1) ~= root .. "/" then return end
  local pos = vim.api.nvim_win_get_cursor(0)
  local text = vim.trim(vim.api.nvim_buf_get_lines(buf, pos[1] - 1, pos[1], false)[1] or "")
  local list = load()[root] or {}
  -- mesmo arquivo e perto: atualiza o ponto em vez de criar outro
  for i, l in ipairs(list) do
    if l.file == file and math.abs(l.line - pos[1]) <= NEAR then table.remove(list, i); break end
  end
  table.insert(list, 1, { file = file, line = pos[1], col = pos[2], text = text })
  while #list > MAX do table.remove(list) end
  all[root] = list
  M.dirty = true
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

local function select(i)
  if not st.items or #st.items == 0 then return end
  st.sel = math.max(1, math.min(i, #st.items))
  pcall(vim.api.nvim_win_set_cursor, st.list_win, { st.sel, 0 })
end

-- o texto atual da linha, se o arquivo estiver aberto (senão, o guardado)
local function line_text(l)
  local buf = vim.fn.bufnr(l.file)
  if buf > 0 and vim.api.nvim_buf_is_loaded(buf) then
    local t = vim.api.nvim_buf_get_lines(buf, l.line - 1, l.line, false)[1]
    if t then return vim.trim(t) end
  end
  return l.text or ""
end

local function render()
  local query = (vim.api.nvim_buf_get_lines(st.input_buf, 0, 1, false)[1] or ""):lower()
  local words = vim.split(query, "%s+", { trimempty = true })
  local root = project()
  local items = {}
  for _, l in ipairs(st.list) do
    local rel = l.file:sub(#root + 2)
    local code = line_text(l)
    local hay = (rel .. " " .. code):lower()
    local ok = true
    for _, w in ipairs(words) do if not hay:find(w, 1, true) then ok = false; break end end
    if ok then table.insert(items, { loc = l, rel = rel, code = code }) end
  end
  st.items = items
  local width = st.width
  local text, marks = {}, {}
  for i, it in ipairs(items) do
    local name = vim.fn.fnamemodify(it.rel, ":t")
    local dir = vim.fn.fnamemodify(it.rel, ":h")
    local head = "  " .. name .. ":" .. it.loc.line
    local headw = 34
    local left = head .. string.rep(" ", math.max(2, headw - vim.fn.strdisplaywidth(head)))
    local dir_w = math.min(vim.fn.strdisplaywidth(dir), math.floor(width * 0.3))
    if vim.fn.strdisplaywidth(dir) > dir_w then dir = "…" .. vim.fn.strcharpart(dir, vim.fn.strchars(dir) - dir_w + 1) end
    local room = width - vim.fn.strdisplaywidth(left) - dir_w - 4
    local code = it.code
    if vim.fn.strdisplaywidth(code) > room then code = vim.fn.strcharpart(code, 0, math.max(0, room - 1)) .. "…" end
    local line = left .. code
    line = line .. string.rep(" ", math.max(2, width - vim.fn.strdisplaywidth(line) - vim.fn.strdisplaywidth(dir) - 1)) .. dir
    table.insert(text, line)
    local r = i - 1
    table.insert(marks, { r, 2, 2 + #name, "RecentLocFile" })
    table.insert(marks, { r, 2 + #name, #head, "RecentLocLine" })
    table.insert(marks, { r, #left, #left + #code, "RecentLocCode" })
    table.insert(marks, { r, #line - #dir, #line, "RecentLocHint" })
  end
  if #text == 0 then
    text = { "", #st.list == 0 and "   Nenhum lugar visitado ainda neste projeto" or "   Nada encontrado" }
    table.insert(marks, { 1, 0, -1, "RecentLocHint" })
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
  select(st.sel or 1)
end

local function activate(i)
  local it = st.items and st.items[i or st.sel]
  if not it then return end
  local loc = it.loc
  close()
  vim.schedule(function()
    local main = require("config.panels").main_win()
    if main then vim.api.nvim_set_current_win(main) end
    vim.cmd.edit(vim.fn.fnameescape(loc.file))
    pcall(vim.api.nvim_win_set_cursor, 0, { loc.line, loc.col or 0 })
    vim.cmd("normal! zz")
  end)
end

function M.open()
  if st.input_win and vim.api.nvim_win_is_valid(st.input_win) then return close() end
  M.record()
  local list = load()[project()] or {}
  -- a posição atual (recém-registrada) não interessa: começa pela anterior
  st = { list = vim.list_slice(list, 2), prev_win = vim.api.nvim_get_current_win() }
  st.width = math.min(130, vim.o.columns - 8)
  local height = math.max(8, math.min(#st.list + 1, math.floor(vim.o.lines * 0.6)))
  local col = math.floor((vim.o.columns - st.width) / 2)
  local row = math.max(2, math.floor(vim.o.lines * 0.12))

  st.input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[st.input_buf].bufhidden = "wipe"
  vim.b[st.input_buf].completion = false
  st.input_win = vim.api.nvim_open_win(st.input_buf, true, {
    relative = "editor", row = row, col = col, width = st.width, height = 1,
    style = "minimal", border = { "╭", "─", "╮", "│", "", "", "", "│" }, zindex = 210,
    title = { { " Recent Locations ", "RecentLocTitle" } }, title_pos = "left",
  })
  vim.wo[st.input_win].winhighlight = "Normal:RecentLocNormal,FloatBorder:RecentLocBorder"
  st.list_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[st.list_buf].bufhidden = "wipe"
  st.list_win = vim.api.nvim_open_win(st.list_buf, false, {
    relative = "editor", row = row + 2, col = col, width = st.width, height = height,
    style = "minimal", border = { "├", "─", "┤", "│", "╯", "─", "╰", "│" }, zindex = 210,
  })
  vim.wo[st.list_win].cursorline = true
  vim.wo[st.list_win].winhighlight = "Normal:RecentLocNormal,FloatBorder:RecentLocBorder,CursorLine:RecentLocSel"

  local ibuf = st.input_buf
  local icon_ns = vim.api.nvim_create_namespace("recent_locations_icon")
  vim.api.nvim_buf_set_extmark(ibuf, icon_ns, 0, 0, {
    virt_text = { { " \u{F0349}  ", "RecentLocHint" } }, virt_text_pos = "inline", right_gravity = false,
  })
  local ph = vim.api.nvim_create_namespace("recent_locations_placeholder")
  local function placeholder()
    vim.api.nvim_buf_clear_namespace(ibuf, ph, 0, -1)
    if (vim.api.nvim_buf_get_lines(ibuf, 0, 1, false)[1] or "") == "" then
      vim.api.nvim_buf_set_extmark(ibuf, ph, 0, 0, { virt_text = { { "Arquivo ou trecho de código", "RecentLocHint" } }, virt_text_pos = "overlay" })
    end
  end
  placeholder()
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = ibuf,
    callback = function() if st.input_buf then placeholder(); st.sel = 1; render() end end,
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
  for _, k in ipairs({ "<Down>", "<C-n>", "<C-j>", "<Tab>" }) do imap(k, function() select((st.sel or 1) + 1) end) end
  for _, k in ipairs({ "<Up>", "<C-p>", "<C-k>", "<S-Tab>" }) do imap(k, function() select((st.sel or 1) - 1) end) end
  imap("<CR>", function() activate() end)
  imap("<Esc>", close)
  -- Cmd+Shift+E de novo desce na lista (como no PhpStorm)
  imap("<D-S-e>", function() select((st.sel or 1) + 1) end)
  imap("<D-E>", function() select((st.sel or 1) + 1) end)
  vim.keymap.set("n", "q", close, { buffer = ibuf })
  -- (arrastar não vira seleção; se a lista estiver em modo visual, o clique e Esc/q valem igual)
  vim.keymap.set({ "n", "x", "i" }, "<LeftDrag>", "<Nop>", { buffer = st.list_buf })
  for _, k in ipairs({ "<Esc>", "q" }) do vim.keymap.set("x", k, close, { buffer = st.list_buf }) end
  vim.keymap.set({ "n", "i", "x" }, "<LeftRelease>", function()
    if vim.fn.mode():match("[vV\22]") then vim.cmd("normal! \27") end
    local p = vim.fn.getmousepos()
    if p.winid == st.list_win then activate(p.line) end
  end, { buffer = st.list_buf })

  st.sel = 1
  render()
  vim.cmd.startinsert()
end

-- Registra ao parar o cursor e ao sair do arquivo; grava em disco de tempos em tempos
local group = vim.api.nvim_create_augroup("recent_locations", { clear = true })
vim.api.nvim_create_autocmd({ "CursorHold", "BufLeave" }, { group = group, callback = function() pcall(M.record) end })
vim.api.nvim_create_autocmd({ "FocusLost", "VimLeavePre" }, {
  group = group,
  callback = function() if M.dirty then M.dirty = false; pcall(save) end end,
})
local timer = vim.uv.new_timer()
timer:start(30000, 30000, vim.schedule_wrap(function() if M.dirty then M.dirty = false; pcall(save) end end))

local function colors()
  local ok, c = pcall(require, "config.palette")
  if not ok then return end
  local set = vim.api.nvim_set_hl
  set(0, "RecentLocNormal", { fg = c.fg, bg = c.bg_float })
  set(0, "RecentLocBorder", { fg = c.border, bg = c.bg_float })
  set(0, "RecentLocTitle", { fg = c.fg, bg = c.bg_float, bold = true })
  set(0, "RecentLocSel", { bg = require("config.palette").sel_row })
  set(0, "RecentLocHint", { fg = c.fg_faint })
  set(0, "RecentLocFile", { fg = require("config.palette").bright, bold = true })
  set(0, "RecentLocLine", { fg = c.fg_dim })
  set(0, "RecentLocCode", { fg = c.fg_dim })
end
colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = colors })

return M
