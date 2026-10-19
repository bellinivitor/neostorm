-- Árvore de resultados dos testes, à esquerda da saída no painel Run (como no PhpStorm):
--   ✗ Feature/ShipmentTest        3/5
--       ✓ cria remessa          0,12s
--       ✗ calcula imposto       0,30s
--           Failed asserting that 10 matches expected 12.
--   ▸ ✓ Unit/MoneyTest            8/8
-- Enter: no teste abre o arquivo na linha dele; na falha vai para onde o teste quebrou;
-- no arquivo abre/fecha. f roda de novo só os que falharam. r repete a última rodada. q fecha.
local M = {}

local ns = vim.api.nvim_create_namespace("test_results")
local I = { ok = "\u{2713}", fail = "\u{2717}", skip = "\u{25CB}", down = "\u{F0140}", right = "\u{F0142}" }
local WIDTH = 52

local st = { groups = {}, collapsed = {}, rows = {} }

local function unxml(s)
  return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&#039;", "'"):gsub("&apos;", "'"):gsub("&#10;", "\n"):gsub("&amp;", "&"))
end

--- Lê o JUnit do Pest: { { file, label, tests = { { name, time, status, message, trace } } } }
function M.parse(path, root)
  local f = io.open(path, "r")
  if not f then return nil end
  local xml = f:read("*a")
  f:close()
  local groups, by_file = {}, {}
  local pos = 1
  while true do
    local s, e, attrs, closed = xml:find("<testcase%s([^>]-)(/?)>", pos)
    if not s then break end
    local body = ""
    if closed ~= "/" then
      local ce = xml:find("</testcase>", e, true)
      body = xml:sub(e + 1, (ce or #xml) - 1)
      pos = ce or #xml
    else
      pos = e + 1
    end
    local function attr(n) local v = attrs:match(n .. '="(.-)"'); return v and unxml(v) or nil end
    local file = (attr("file") or ""):gsub("::.*$", "")
    if file ~= "" and file:sub(1, 1) ~= "/" and root then file = root .. "/" .. file end
    local fail = body:match("<failure[^>]*>(.-)</failure>") or body:match("<error[^>]*>(.-)</error>")
    local t = {
      name = attr("name") or "?",
      time = tonumber(attr("time") or "") or 0,
      status = fail and "fail" or (body:find("<skipped") and "skip" or "ok"),
      trace = fail and unxml(fail) or nil,
    }
    if t.trace then
      -- primeira linha útil da falha (sem o nome da exceção sozinho)
      for l in t.trace:gmatch("[^\n]+") do
        l = vim.trim(l)
        if l ~= "" and not l:match("^[%w\\]+Exception$") and not l:match("^[%w\\]+Error$") then t.message = l; break end
      end
    end
    local key = file ~= "" and file or (attr("class") or "?")
    if not by_file[key] then
      local label = file ~= "" and file:gsub("^.*/tests/", ""):gsub("%.php$", "") or key
      by_file[key] = { file = file ~= "" and file or nil, label = label, tests = {} }
      table.insert(groups, by_file[key])
    end
    table.insert(by_file[key].tests, t)
  end
  for _, g in ipairs(groups) do
    g.fails, g.oks = 0, 0
    for _, t in ipairs(g.tests) do
      if t.status == "fail" then g.fails = g.fails + 1 elseif t.status == "ok" then g.oks = g.oks + 1 end
    end
  end
  -- arquivos com falha primeiro
  table.sort(groups, function(a, b)
    if (a.fails > 0) ~= (b.fails > 0) then return a.fails > 0 end
    return a.label < b.label
  end)
  return groups
end

local function seconds(t)
  if t >= 1 then return (string.format("%.1fs", t):gsub("%.", ",")) end
  return string.format("%dms", math.floor(t * 1000 + 0.5))
end

local function valid(w) return w and vim.api.nvim_win_is_valid(w) end

local function render()
  if not (st.buf and vim.api.nvim_buf_is_valid(st.buf)) then return end
  local width = valid(st.win) and vim.api.nvim_win_get_width(st.win) or WIDTH
  local text, marks, rows = {}, {}, {}
  local function line(s, hls, row)
    table.insert(text, s)
    for _, h in ipairs(hls) do table.insert(marks, { #text - 1, h[1], h[2], h[3] }) end
    rows[#text] = row
  end
  local function right(left, r) return left .. string.rep(" ", math.max(2, width - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(r) - 1)) .. r end

  if #st.groups == 0 then
    line("", {}, nil)
    line("  " .. (st.running and "Rodando…" or "Nenhum resultado. O relatório do Pest não foi gerado."), { { 0, -1, "TestResDim" } }, nil)
  end
  for _, g in ipairs(st.groups) do
    local open = not st.collapsed[g.label]
    local icon = g.fails > 0 and I.fail or I.ok
    local arrow = (open and I.down or I.right) .. " "
    local left = " " .. arrow .. icon .. " " .. g.label
    local count = (g.oks .. "/" .. #g.tests)
    local s = right(left, count)
    local a0 = 1 + #arrow
    line(s, {
      { 1, a0, "TestResDim" },
      { a0, a0 + #icon, g.fails > 0 and "TestResFail" or "TestResOk" },
      { a0 + #icon + 1, #left, "TestResFile" },
      { #s - #count, #s, "TestResDim" },
    }, { kind = "group", group = g })
    if open then
      for _, t in ipairs(g.tests) do
        local ticon = t.status == "fail" and I.fail or (t.status == "skip" and I.skip or I.ok)
        local tl = "     " .. ticon .. " " .. t.name
        local time = seconds(t.time)
        local room = width - #time - 8
        if vim.fn.strdisplaywidth(tl) > room then tl = vim.fn.strcharpart(tl, 0, room - 1) .. "…" end
        local ts = right(tl, time)
        line(ts, {
          { 5, 5 + #ticon, t.status == "fail" and "TestResFail" or (t.status == "skip" and "TestResDim" or "TestResOk") },
          { 5 + #ticon + 1, #tl, t.status == "skip" and "TestResDim" or "TestResName" },
          { #ts - #time, #ts, "TestResDim" },
        }, { kind = "test", group = g, test = t })
        if t.status == "fail" and t.message then
          local msg = "         " .. t.message
          if vim.fn.strdisplaywidth(msg) > width - 1 then msg = vim.fn.strcharpart(msg, 0, width - 2) .. "…" end
          line(msg, { { 0, -1, "TestResMessage" } }, { kind = "failure", group = g, test = t })
        end
      end
    end
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
  if valid(st.win) then
    local fails, oks, total = 0, 0, 0
    for _, g in ipairs(st.groups) do fails, oks, total = fails + g.fails, oks + g.oks, total + #g.tests end
    local bar = " Testes  "
    if st.running then bar = bar .. "%#TestResBarDim#rodando…"
    elseif total > 0 then
      bar = bar .. (fails > 0 and ("%#TestResBarFail#" .. I.fail .. " " .. fails .. " falh" .. (fails == 1 and "ou" or "aram") .. "  ") or "")
        .. "%#TestResBarOk#" .. I.ok .. " " .. oks .. (oks == 1 and " passou" or " passaram")
        .. "%#TestResBarDim#  " .. seconds(st.time or 0)
    end
    vim.wo[st.win].winbar = bar .. "%#TestResBarDim#%=" .. (fails > 0 and "f falhos  " or "") .. "r repetir "
  end
end

-- abre o arquivo na janela de código, na linha pedida
local function goto_file(file, line)
  if not file then return end
  local main = require("config.panels").main_win()
  if main then vim.api.nvim_set_current_win(main) end
  vim.cmd("edit " .. vim.fn.fnameescape(file))
  pcall(vim.api.nvim_win_set_cursor, 0, { line or 1, 0 })
  vim.cmd("normal! zz")
end

-- linha do teste no arquivo: test('nome') / it('nome') (o Pest chama o it() de "it nome")
local function test_line(file, name)
  local ok, lines = pcall(vim.fn.readfile, file)
  if not ok then return 1 end
  local raw = name:gsub("^it ", ""):gsub(" with data set .*$", ""):gsub(" with %(.*$", "")
  for i, l in ipairs(lines) do
    local q, n = l:match("^%s*%a+%(%s*(['\"])(.-)%1")
    if n and (n == name or n == raw) then return i end
  end
  return 1
end

-- onde o teste quebrou: o primeiro "arquivo.php:linha" da falha que está dentro do projeto
local function failure_location(t, g)
  for path, ln in (t.trace or ""):gmatch("(/[^%s:]+%.php):(%d+)") do
    if not path:find("/vendor/", 1, true) then return path, tonumber(ln) end
  end
  return g.file, g.file and test_line(g.file, t.name) or 1
end

local function activate()
  local row = st.rows[vim.api.nvim_win_get_cursor(0)[1]]
  if not row then return end
  if row.kind == "group" then
    st.collapsed[row.group.label] = not st.collapsed[row.group.label]
    return render()
  end
  if row.kind == "failure" then return goto_file(failure_location(row.test, row.group)) end
  goto_file(row.group.file, row.group.file and test_line(row.group.file, row.test.name))
end

local function rerun_failed()
  local names = {}
  for _, g in ipairs(st.groups) do
    for _, t in ipairs(g.tests) do if t.status == "fail" then table.insert(names, t.name) end end
  end
  if #names == 0 then return vim.notify("Nenhum teste falhou.", vim.log.levels.INFO, { title = "Testes" }) end
  require("config.tests").run_failed(names)
end

local function ensure_window()
  local run = require("config.run_panel")
  if not valid(run.win) then return false end
  if not (st.buf and vim.api.nvim_buf_is_valid(st.buf)) then
    st.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[st.buf].bufhidden = "hide"
    vim.bo[st.buf].filetype = "test_results"
    local function map(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = st.buf, nowait = true }) end
    map("<CR>", activate)
    map("<2-LeftMouse>", require("config.panels").after_click(activate))
    map("f", rerun_failed)
    map("r", function() require("config.tests").again() end)
    map("q", M.close)
  end
  if valid(st.win) and vim.api.nvim_win_get_tabpage(st.win) == vim.api.nvim_get_current_tabpage() then return true end
  local cur = vim.api.nvim_get_current_win()
  st.win = vim.api.nvim_open_win(st.buf, false, { split = "left", win = run.win, width = math.min(WIDTH, math.floor(vim.api.nvim_win_get_width(run.win) * 0.45)) })
  local wo = vim.wo[st.win]
  wo.number, wo.relativenumber, wo.signcolumn, wo.statuscolumn = false, false, "no", ""
  wo.foldcolumn, wo.wrap, wo.cursorline, wo.winfixwidth, wo.winfixheight = "0", false, true, true, true
  wo.winhighlight = "Normal:TermPanel,NormalNC:TermPanel,EndOfBuffer:TermPanel,CursorLine:TestResSel,WinBar:TermTabBar,WinBarNC:TermTabBar"
  require("config.panels").mark(st.win, st.buf)
  -- a árvore some junto com o painel Run
  local run_win, tree_win = run.win, st.win
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(run_win), once = true,
    callback = function() vim.schedule(function() if valid(tree_win) then pcall(vim.api.nvim_win_close, tree_win, true) end end) end,
  })
  if vim.api.nvim_win_is_valid(cur) then vim.api.nvim_set_current_win(cur) end
  return true
end

--- Marca a rodada como em andamento (a árvore mostra "rodando…")
function M.start()
  st.running = true
  st.groups = {}
  vim.schedule(function() if ensure_window() then render() end end)
end

--- Mostra os resultados de um relatório JUnit
function M.show(xml, root)
  st.running = false
  st.groups = M.parse(xml, root) or {}
  st.time = 0
  for _, g in ipairs(st.groups) do
    for _, t in ipairs(g.tests) do st.time = st.time + t.time end
    -- arquivos que passaram ficam recolhidos quando há falhas em outros
    st.collapsed[g.label] = g.fails == 0 and #st.groups > 1 or nil
  end
  if ensure_window() then render() end
  return st.groups
end

function M.close()
  if valid(st.win) then pcall(vim.api.nvim_win_close, st.win, true) end
  st.win = nil
end

vim.api.nvim_create_autocmd("WinResized", {
  group = vim.api.nvim_create_augroup("test_results", { clear = true }),
  callback = function() if valid(st.win) then render() end end,
})

local function colors()
  local ok, c = pcall(require, "config.palette")
  if not ok then return end
  local set = vim.api.nvim_set_hl
  set(0, "TestResOk", { fg = c.hint })
  set(0, "TestResFail", { fg = c.error })
  set(0, "TestResFile", { fg = c.fg })
  set(0, "TestResName", { fg = c.fg })
  set(0, "TestResDim", { fg = c.fg_faint })
  set(0, "TestResMessage", { fg = "#C9616B" })
  set(0, "TestResSel", { bg = require("config.palette").sel_row })
  set(0, "TestResBarOk", { fg = c.hint, bg = c.bg })
  set(0, "TestResBarFail", { fg = c.error, bg = c.bg })
  set(0, "TestResBarDim", { fg = c.fg_faint, bg = c.bg })
end
colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = colors })

return M
