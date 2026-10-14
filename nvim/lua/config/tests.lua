-- Testes como no PhpStorm (Pest): ▶ na margem ao lado de cada test()/it() e na 1ª linha
-- (arquivo inteiro). Clicar roda no painel Run, com o PHP do projeto; no fim a margem
-- troca o ▶ por ✓ ou ✗ e a mensagem de falha aparece como erro na linha do teste.
--   <leader>tn teste sob o cursor · <leader>tf arquivo · <leader>tl repete · <leader>ts suíte
local M = {}

local ns = vim.api.nvim_create_namespace("pest_tests")
local diag_ns = vim.api.nvim_create_namespace("pest_results")
local I = { run = "\u{25B6}", all = "\u{23F5}\u{23F5}", ok = "\u{2713}", fail = "\u{2717}", running = "\u{25CC}" }

-- resultados por arquivo: results[path][nome do teste] = "ok" | "fail" | "running"
local results = {}
M.last = nil

local function project_root(path) return vim.fs.root(path, { "artisan", "composer.json" }) end

local function is_test_file(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  return vim.bo[buf].filetype == "php" and name:match("/tests/") ~= nil and name:match("%.php$") ~= nil
    and not name:match("/tests/Pest%.php$") and not name:match("/tests/TestCase%.php$")
end

-- test('nome', …) / it('nome', …): { name, line } (it() vira "it nome", como o Pest chama)
local function scan(buf)
  local tests = {}
  for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local kind, q, name = l:match("^%s*(%a+)%(%s*(['\"])(.-)%2")
    if (kind == "test" or kind == "it") and name then
      table.insert(tests, { name = kind == "it" and ("it " .. name) or name, raw = name, line = i })
    end
  end
  return tests
end

-- ---------------------------------------------------------------------------
-- Margem
-- ---------------------------------------------------------------------------
function M.refresh(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) or not is_test_file(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local tests = scan(buf)
  if #tests == 0 then return end
  local res = results[vim.api.nvim_buf_get_name(buf)] or {}
  local function sign(line, text, hl)
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, line - 1, 0, { sign_text = text, sign_hl_group = hl, priority = 50 })
  end
  -- arquivo inteiro: na 1ª linha (fica ✓/✗ quando todos rodaram)
  local all_ok, any_fail, all_ran = true, false, true
  for _, t in ipairs(tests) do
    local r = res[t.name]
    if r ~= "ok" then all_ok = false end
    if r == "fail" then any_fail = true end
    if not r then all_ran = false end
  end
  sign(1, any_fail and I.fail or (all_ran and all_ok and I.ok or I.all), any_fail and "TestFail" or (all_ran and all_ok and "TestOk" or "TestRun"))
  for _, t in ipairs(tests) do
    local r = res[t.name]
    if r == "ok" then sign(t.line, I.ok, "TestOk")
    elseif r == "fail" then sign(t.line, I.fail, "TestFail")
    elseif r == "running" then sign(t.line, I.running, "TestRunning")
    else sign(t.line, I.run, "TestRun") end
  end
end

-- ---------------------------------------------------------------------------
-- Relatório JUnit do Pest → ✓/✗ e mensagens
-- ---------------------------------------------------------------------------
local function unxml(s)
  return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&#039;", "'"):gsub("&apos;", "'"):gsub("&amp;", "&"))
end

local function parse_junit(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local xml = f:read("*a")
  f:close()
  local cases = {}
  local pos = 1
  while true do
    local s, e, attrs, closed = xml:find("<testcase%s([^>]-)(/?)>", pos)
    if not s then break end
    local name = unxml(attrs:match('name="(.-)"') or "")
    local body = ""
    if closed ~= "/" then
      local ce = xml:find("</testcase>", e, true)
      body = xml:sub(e + 1, (ce or #xml) - 1)
      pos = ce or #xml
    else
      pos = e + 1
    end
    local fail = body:match("<failure[^>]*>(.-)</failure>") or body:match("<error[^>]*>(.-)</error>")
    local skipped = body:find("<skipped") ~= nil
    table.insert(cases, { name = name, fail = fail and unxml(fail) or nil, skipped = skipped })
  end
  return cases
end

local function apply_results(file, tests, xml)
  local cases = parse_junit(xml)
  local res = results[file] or {}
  local diags = {}
  for _, t in ipairs(tests) do
    if res[t.name] == "running" then res[t.name] = nil end
    for _, c in ipairs(cases or {}) do
      -- datasets viram "nome with data set …": compara pelo começo
      if c.name == t.name or c.name:sub(1, #t.name) == t.name then
        if c.fail then
          res[t.name] = "fail"
          local msg = vim.trim(c.fail):gsub("\n.*", "")
          table.insert(diags, { lnum = t.line - 1, col = 0, severity = vim.diagnostic.severity.ERROR, source = "Pest", message = msg })
        elseif not c.skipped and res[t.name] ~= "fail" then
          res[t.name] = "ok"
        end
      end
    end
  end
  results[file] = res
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b) == file then
      vim.diagnostic.set(diag_ns, b, diags)
      M.refresh(b)
    end
  end
  return #diags
end

-- ---------------------------------------------------------------------------
-- Rodar
-- ---------------------------------------------------------------------------
-- regex do --filter (o Pest compara com o nome do teste)
local function filter_regex(name)
  return (name:gsub("[%^%$%(%)%.%[%]%*%+%-%?%{%}%|/\\]", "\\%0"))
end

--- Comando para rodar (separado para poder trocar nos testes desta configuração)
function M.command(root, target, filter, xml)
  local parts = { "php", "vendor/bin/pest", vim.fn.shellescape(target), "--colors=always", "--log-junit", vim.fn.shellescape(xml) }
  if filter then vim.list_extend(parts, { "--filter", vim.fn.shellescape(filter) }) end
  return table.concat(parts, " ")
end

--- target: arquivo ou pasta; test: { name } ou nil (todos do alvo)
function M.run(target, test)
  local root = project_root(target)
  if not root then return vim.notify("Não achei o projeto deste teste", vim.log.levels.WARN, { title = "Testes" }) end
  M.last = { target = target, test = test }
  local rel = target:sub(#root + 2)
  local is_file = target:match("%.php$") ~= nil
  local tests = {}
  if is_file then
    local buf = vim.fn.bufnr(target)
    tests = buf > 0 and scan(buf) or {}
    if test then tests = vim.tbl_filter(function(t) return t.name == test.name end, tests) end
    local res = results[target] or {}
    for _, t in ipairs(tests) do res[t.name] = "running" end
    results[target] = res
    if buf > 0 then M.refresh(buf) end
  end
  local xml = vim.fn.stdpath("cache") .. "/pest-" .. vim.fn.getpid() .. ".xml"
  local cmd = "rm -f " .. vim.fn.shellescape(xml) .. "; " .. M.command(root, rel, test and filter_regex(test.name), xml)
  local title = test and ("Pest: " .. test.name) or ("Pest: " .. (rel ~= "" and rel or "suíte"))
  local run = require("config.run_panel")
  local i = run.find(title)
  if i then run.close(i) end
  run.new({
    name = title, cwd = root, cmd = { vim.o.shell, "-c", cmd }, focus = false,
    on_exit = function()
      if not is_file then
        -- suíte/pasta: atualiza os arquivos abertos
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(b) and is_test_file(b) then apply_results(vim.api.nvim_buf_get_name(b), scan(b), xml) end
        end
        return
      end
      local fails = apply_results(target, tests, xml)
      vim.notify(fails > 0 and (fails .. " teste(s) falharam") or "Testes passaram", fails > 0 and vim.log.levels.WARN or vim.log.levels.INFO, { title = title })
    end,
  })
end

local function current_test(buf)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local best
  for _, t in ipairs(scan(buf)) do if t.line <= line then best = t end end
  return best
end

function M.nearest()
  local buf = vim.api.nvim_get_current_buf()
  if not is_test_file(buf) then return vim.notify("Abra um arquivo de teste", vim.log.levels.INFO, { title = "Testes" }) end
  local t = current_test(buf)
  M.run(vim.api.nvim_buf_get_name(buf), t)
end

function M.file()
  local buf = vim.api.nvim_get_current_buf()
  if not is_test_file(buf) then return vim.notify("Abra um arquivo de teste", vim.log.levels.INFO, { title = "Testes" }) end
  M.run(vim.api.nvim_buf_get_name(buf))
end

function M.suite()
  local root = project_root(vim.api.nvim_buf_get_name(0) ~= "" and vim.api.nvim_buf_get_name(0) or vim.fn.getcwd()) or vim.fn.getcwd()
  M.run(root .. "/tests")
end

function M.again()
  if not M.last then return vim.notify("Nenhum teste rodou ainda", vim.log.levels.INFO, { title = "Testes" }) end
  M.run(M.last.target, M.last.test)
end

-- Clique no ▶ da margem (chamado pela coluna da esquerda, config/gitgutter.lua)
function M.click()
  local pos = vim.fn.getmousepos()
  local buf = vim.api.nvim_win_get_buf(pos.winid)
  if not is_test_file(buf) then return end
  local file = vim.api.nvim_buf_get_name(buf)
  if pos.line == 1 then return M.run(file) end
  for _, t in ipairs(scan(buf)) do
    if t.line == pos.line then return M.run(file, t) end
  end
end
function _G.TestGutterClick() vim.schedule(M.click) end
M.ns = ns

-- (FileType: ao abrir o arquivo o tipo "php" ainda não foi definido no BufReadPost)
vim.api.nvim_create_autocmd({ "FileType", "BufReadPost", "BufWritePost", "InsertLeave", "TextChanged" }, {
  group = vim.api.nvim_create_augroup("pest_tests", { clear = true }),
  callback = function(ev) M.refresh(ev.buf) end,
})

local function colors()
  local ok, c = pcall(require, "config.palette")
  if not ok then return end
  local set = vim.api.nvim_set_hl
  set(0, "TestRun", { fg = c.hint })
  set(0, "TestOk", { fg = c.hint })
  set(0, "TestFail", { fg = c.error })
  set(0, "TestRunning", { fg = c.accent })
end
colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = colors })

return M
