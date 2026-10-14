-- Painel Problems (Cmd+6 no PhpStorm): erros e avisos dos arquivos, agrupados por arquivo.
--    Problems   ✗ 3 erros  ⚠ 12 avisos                      a analisa os arquivos alterados
--   ▾ ShipmentController.php  app/Http/Controllers/Client   2
--       ✗  38:5   Undefined method 'foo'.                                 intelephense
-- Os servidores de linguagem só analisam arquivos abertos; "a" abre em segundo plano os
-- arquivos alterados no git para eles serem analisados também.
local M = {}

local ns = vim.api.nvim_create_namespace("problems_panel")
local SEV = vim.diagnostic.severity
local ICON = { [SEV.ERROR] = "\u{2717}", [SEV.WARN] = "\u{26A0}", [SEV.INFO] = "\u{2139}", [SEV.HINT] = "\u{2022}" }
local HL = { [SEV.ERROR] = "ProblemsError", [SEV.WARN] = "ProblemsWarn", [SEV.INFO] = "ProblemsInfo", [SEV.HINT] = "ProblemsHint" }

local st = { collapsed = {}, rows = {} }

local function valid() return st.win and vim.api.nvim_win_is_valid(st.win) end
function M.is_open() return valid() end

local function root() return vim.fn.getcwd() end

-- problemas por arquivo (só arquivos de verdade do projeto)
local function collect()
  local r = root()
  local files, total = {}, { [SEV.ERROR] = 0, [SEV.WARN] = 0, [SEV.INFO] = 0, [SEV.HINT] = 0 }
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" and name:sub(1, #r + 1) == r .. "/" then
      local diags = vim.diagnostic.get(buf)
      if #diags > 0 then
        table.sort(diags, function(a, b)
          if a.severity ~= b.severity then return a.severity < b.severity end
          return a.lnum < b.lnum
        end)
        table.insert(files, { buf = buf, path = name, rel = name:sub(#r + 2), diags = diags, worst = diags[1].severity })
        for _, d in ipairs(diags) do total[d.severity] = (total[d.severity] or 0) + 1 end
      end
    end
  end
  -- arquivos com erro primeiro, depois por nome
  table.sort(files, function(a, b)
    if a.worst ~= b.worst then return a.worst < b.worst end
    return a.rel < b.rel
  end)
  return files, total
end

local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

function M.render()
  if not valid() then return end
  local files, total = collect()
  local width = vim.api.nvim_win_get_width(st.win)
  local text, marks, rows = {}, {}, {}
  for _, f in ipairs(files) do
    local name = vim.fn.fnamemodify(f.rel, ":t")
    local dir = vim.fn.fnamemodify(f.rel, ":h")
    local arrow = st.collapsed[f.path] and "\u{F0142}" or "\u{F0140}"
    local head = " " .. arrow .. " " .. name .. "  "
    local line = head .. dir .. "   " .. #f.diags
    table.insert(text, line)
    rows[#text] = { file = f }
    table.insert(marks, { #text - 1, 0, #head, "ProblemsFile" })
    table.insert(marks, { #text - 1, #head, #head + #dir, "ProblemsHint" })
    table.insert(marks, { #text - 1, #line - #tostring(#f.diags), #line, "ProblemsCount" })
    if not st.collapsed[f.path] then
      for _, d in ipairs(f.diags) do
        local icon = ICON[d.severity] or "•"
        local pos = string.format("%d:%d", d.lnum + 1, d.col + 1)
        local left = "     " .. icon .. "  " .. pos .. string.rep(" ", math.max(1, 8 - #pos)) .. " "
        local source = d.source or ""
        local msg = (d.message or ""):gsub("\n.*", "")
        local room = width - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(source) - 3
        if vim.fn.strdisplaywidth(msg) > room then msg = vim.fn.strcharpart(msg, 0, math.max(10, room - 1)) .. "…" end
        local l = left .. msg
        l = l .. string.rep(" ", math.max(2, width - vim.fn.strdisplaywidth(l) - vim.fn.strdisplaywidth(source) - 1)) .. source
        table.insert(text, l)
        rows[#text] = { file = f, diag = d }
        local r = #text - 1
        table.insert(marks, { r, 5, 5 + #icon, HL[d.severity] or "ProblemsHint" })
        table.insert(marks, { r, 5 + #icon + 2, 5 + #icon + 2 + #pos, "ProblemsHint" })
        table.insert(marks, { r, #left, #left + #msg, "ProblemsText" })
        table.insert(marks, { r, #l - #source, #l, "ProblemsHint" })
      end
    end
  end
  if #text == 0 then
    text = { "", "   Nenhum problema nos arquivos abertos.  Aperte a para analisar os arquivos alterados no git." }
    table.insert(marks, { 1, 0, -1, "ProblemsHint" })
  end
  st.rows = rows
  vim.bo[st.buf].modifiable = true
  vim.api.nvim_buf_set_lines(st.buf, 0, -1, false, text)
  vim.bo[st.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(st.buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    local len = #text[m[1] + 1]
    local e = m[3] == -1 and len or math.min(m[3], len)
    if m[2] < e then vim.api.nvim_buf_set_extmark(st.buf, ns, m[1], m[2], { end_col = e, hl_group = m[4] }) end
  end
  local e, w = total[SEV.ERROR] or 0, total[SEV.WARN] or 0
  vim.wo[st.win].winbar = "%#TermTabTitle# Problems  "
    .. "%#ProblemsError#" .. ICON[SEV.ERROR] .. " %#ProblemsBar#" .. plural(e, "erro", "erros") .. "   "
    .. "%#ProblemsWarn#" .. ICON[SEV.WARN] .. " %#ProblemsBar#" .. plural(w, "aviso", "avisos")
    .. (st.analyzing and ("   %#ProblemsBar#analisando " .. st.analyzing .. " arquivo(s)…") or "")
    .. "%=%#ProblemsBar#a analisa os arquivos alterados "
end

-- ---------------------------------------------------------------------------
-- Ações
-- ---------------------------------------------------------------------------
local function activate(line)
  local row = st.rows[line or vim.api.nvim_win_get_cursor(st.win)[1]]
  if not row then return end
  if not row.diag then
    st.collapsed[row.file.path] = not st.collapsed[row.file.path]
    return M.render()
  end
  local main = require("config.panels").main_win()
  if main then vim.api.nvim_set_current_win(main) else vim.cmd("wincmd k") end
  vim.cmd.edit(vim.fn.fnameescape(row.file.path))
  pcall(vim.api.nvim_win_set_cursor, 0, { row.diag.lnum + 1, row.diag.col })
  vim.cmd("normal! zz")
end

-- Abre em segundo plano os arquivos alterados no git (o LSP analisa e o painel mostra)
function M.analyze_changed()
  local r = root()
  local out = vim.system({ "git", "status", "--porcelain", "--untracked-files=all" }, { cwd = r, text = true }):wait()
  if out.code ~= 0 then return vim.notify("Esta pasta não é um repositório git", vim.log.levels.WARN, { title = "Problems" }) end
  local files = {}
  for line in (out.stdout or ""):gmatch("[^\n]+") do
    local status, path = line:sub(1, 2), line:sub(4):gsub("^.* %-> ", "")
    if not status:find("D") and path:match("%.%a+$") then
      local ext = path:match("%.(%a+)$")
      if ({ php = true, vue = true, js = true, ts = true, tsx = true, jsx = true })[ext] then table.insert(files, r .. "/" .. path) end
    end
  end
  if #files == 0 then return vim.notify("Nenhum arquivo PHP/JS/Vue alterado", vim.log.levels.INFO, { title = "Problems" }) end
  st.analyzing = #files
  M.render()
  for _, f in ipairs(files) do
    local buf = vim.fn.bufadd(f)
    if not vim.api.nvim_buf_is_loaded(buf) then
      vim.bo[buf].buflisted = false -- não vira aba
      pcall(vim.fn.bufload, buf)
      -- dispara o FileType para o LSP conectar no arquivo
      vim.api.nvim_buf_call(buf, function() pcall(vim.cmd, "filetype detect") end)
    end
  end
  vim.defer_fn(function() st.analyzing = nil; M.render() end, 4000)
end

-- ---------------------------------------------------------------------------
-- Janela
-- ---------------------------------------------------------------------------
function M.close()
  if valid() then pcall(vim.api.nvim_win_close, st.win, true) end
  st.win = nil
end

function M.open()
  if valid() then return vim.api.nvim_set_current_win(st.win) end
  -- mesmo lugar do Terminal e do Run (embaixo): esconde eles
  for _, mod in ipairs({ "config.terminal", "config.run_panel" }) do
    local ok, p = pcall(require, mod)
    if ok and p.is_open() then p.hide() end
  end
  if not (st.buf and vim.api.nvim_buf_is_valid(st.buf)) then
    st.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[st.buf].bufhidden = "hide"
    vim.bo[st.buf].filetype = "problems"
    local function map(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = st.buf, nowait = true }) end
    map("<CR>", function() activate() end)
    map("<2-LeftMouse>", require("config.panels").after_click(function() activate() end))
    map("a", M.analyze_changed)
    map("q", M.close)
    map("<D-w>", M.close)
  end
  st.win = vim.api.nvim_open_win(st.buf, true, { split = "below", win = -1, height = math.max(8, math.floor(vim.o.lines * 0.28)) })
  local wo = vim.wo[st.win]
  wo.number, wo.relativenumber, wo.signcolumn, wo.statuscolumn = false, false, "no", ""
  wo.foldcolumn, wo.wrap, wo.cursorline, wo.winfixheight = "0", false, true, true
  wo.winhighlight = "Normal:TermPanel,NormalNC:TermPanel,CursorLine:ProblemsSel,WinBar:TermTabBar,WinBarNC:TermTabBar"
  require("config.panels").mark(st.win, st.buf)
  M.render()
  pcall(function() require("config.activity_bar").ensure() end)
end

function M.toggle()
  if valid() then return M.close() end
  M.open()
end

-- atualiza sozinho quando os problemas mudam (agrupando mudanças seguidas)
local pending = false
vim.api.nvim_create_autocmd("DiagnosticChanged", {
  group = vim.api.nvim_create_augroup("problems_panel", { clear = true }),
  callback = function()
    if not valid() or pending then return end
    pending = true
    vim.defer_fn(function() pending = false; M.render() end, 200)
  end,
})
vim.api.nvim_create_autocmd("WinClosed", {
  callback = function(ev) if st.win and tonumber(ev.match) == st.win then st.win = nil end end,
})

local function colors()
  local ok, c = pcall(require, "config.palette")
  if not ok then return end
  local set = vim.api.nvim_set_hl
  set(0, "ProblemsFile", { fg = "#DFE1E5", bold = true })
  set(0, "ProblemsText", { fg = c.fg })
  set(0, "ProblemsHint", { fg = c.fg_faint })
  set(0, "ProblemsCount", { fg = c.fg_dim })
  set(0, "ProblemsError", { fg = c.error, bg = c.bg })
  set(0, "ProblemsWarn", { fg = c.warn, bg = c.bg })
  set(0, "ProblemsInfo", { fg = c.info })
  set(0, "ProblemsBar", { fg = c.fg_dim, bg = c.bg })
  set(0, "ProblemsSel", { bg = "#2E436E" })
end
colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = colors })

return M
