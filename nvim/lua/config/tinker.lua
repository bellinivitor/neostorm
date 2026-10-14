-- Tinker na seleção (Cmd+Option+T): roda o trecho selecionado (ou a linha atual) com o
-- `php artisan tinker` do projeto e mostra o resultado num popup.
--   Shipment::find(10)->status     →  "delivered"
-- Uma expressão só vira dump(...) para mostrar o valor. Se o código parece alterar dados
-- (save, delete, update, create…), pede confirmação antes: o tinker usa o banco do .env.
local M = {}

local ns = vim.api.nvim_create_namespace("tinker_result")

-- palavras que indicam que o código altera dados ou dispara efeitos
local WRITES = {
  "save%(", "delete%(", "update%(", "create%(", "insert%(", "upsert%(", "truncate%(", "forceDelete%(",
  "destroy%(", "increment%(", "decrement%(", "restore%(", "sync%(", "attach%(", "detach%(", "push%(",
  "updateOrCreate%(", "firstOrCreate%(", "createMany%(", "saveMany%(", "DB::statement", "DB::unprepared",
  "DB::table%(.-%)%->%s*[uid]", "Artisan::call", "dispatch", "Mail::", "Notification::", "notify%(",
  "Storage::delete", "Storage::put", "Cache::flush", "Cache::forget", "Http::post", "Http::put", "Http::delete",
  "exec%(", "shell_exec", "system%(", "unlink%(",
}

local function looks_like_write(code)
  for _, p in ipairs(WRITES) do
    if code:find(p) then return p:gsub("%%", "") end
  end
end

local function strip_ansi(s) return (s:gsub("\27%[[%d;]*[A-Za-z]", "")) end

-- uma expressão só (sem ; no meio) vira dump(); senão roda como está
local STATEMENTS = { ["if"] = true, foreach = true, ["for"] = true, ["while"] = true, ["function"] = true, echo = true, ["return"] = true, use = true }

local function wrap(code)
  local c = vim.trim(code):gsub(";%s*$", "")
  local first = c:match("^([%a_]+)")
  local assignment = c:match("^%$[%w_]+%s*=[^=>]") ~= nil
  if not c:find(";") and not assignment and not STATEMENTS[first or ""] then
    return "dump(" .. c .. ");", true
  end
  return vim.trim(code):match(";%s*$") and vim.trim(code) or (vim.trim(code) .. ";"), false
end

local function show(code, output, failed, ms)
  local text, marks = {}, {}
  local code_lines = vim.split(vim.trim(code), "\n", { plain = true })
  for _, l in ipairs(code_lines) do
    table.insert(text, " " .. l)
    table.insert(marks, { #text - 1, 0, -1, "TinkerCode" })
  end
  table.insert(text, "")
  local out_lines = vim.split(vim.trim(output) ~= "" and vim.trim(output) or "(sem saída)", "\n", { plain = true })
  for _, l in ipairs(out_lines) do
    table.insert(text, " " .. l)
    table.insert(marks, { #text - 1, 0, -1, failed and "TinkerError" or "TinkerOut" })
  end
  local width = 40
  for _, l in ipairs(text) do width = math.max(width, vim.fn.strdisplaywidth(l) + 2) end
  width = math.min(width, vim.o.columns - 8)
  local height = math.min(#text, vim.o.lines - 8)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
  vim.bo[buf].modifiable = false
  for _, m in ipairs(marks) do
    local len = #text[m[1] + 1]
    local e = m[3] == -1 and len or math.min(m[3], len)
    if m[2] < e then vim.api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = e, hl_group = m[4] }) end
  end
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor", row = 1, col = 0, width = width, height = height,
    style = "minimal", border = "rounded", zindex = 220,
    title = { { " Tinker ", "TinkerTitle" }, { ms .. " ms ", "TinkerNote" } }, title_pos = "left",
    footer = { { " y copia o resultado   q fecha ", "TinkerNote" } }, footer_pos = "right",
  })
  vim.wo[win].winhighlight = "Normal:TinkerNormal,FloatBorder:TinkerBorder"
  vim.wo[win].wrap = false
  local function close() if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end end
  local function map(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true }) end
  map("q", close)
  map("<Esc>", close)
  map("y", function()
    vim.fn.setreg("+", vim.trim(output))
    vim.notify("Resultado copiado", vim.log.levels.INFO, { title = "Tinker" })
  end)
  vim.api.nvim_create_autocmd("WinLeave", { buffer = buf, once = true, callback = function() vim.schedule(close) end })
  return { text = text, win = win }
end

--- Roda o código no tinker do projeto. opts.on_done(result) é chamado com o popup aberto.
function M.run(code, opts)
  opts = opts or {}
  code = vim.trim(code or "")
  if code == "" then return end
  local root = vim.fs.root(vim.api.nvim_buf_get_name(0), { "artisan" }) or vim.fs.root(vim.fn.getcwd(), { "artisan" })
  if not root then return vim.notify("Não é um projeto Laravel (sem artisan)", vim.log.levels.WARN, { title = "Tinker" }) end
  local write = looks_like_write(code)
  if write and not opts.force then
    local ok = vim.fn.confirm("Este código parece alterar dados (" .. write .. ").\nO tinker usa o banco do .env deste projeto. Rodar mesmo assim?",
      "&Rodar\n&Cancelar", 2, "Warning")
    if ok ~= 1 then return end
  end
  local php = require("config.project_php").bin(root) or "php"
  local wrapped = wrap(code)
  local started = vim.uv.now()
  vim.notify("Rodando no tinker…", vim.log.levels.INFO, { title = "Tinker", id = "tinker" })
  vim.system({ php, "-d", "error_reporting=0", "-d", "display_errors=0", "artisan", "tinker", "--execute", wrapped },
    { cwd = root, text = true, timeout = 60000, env = { NO_COLOR = "1" } }, function(r)
      vim.schedule(function()
        local ms = vim.uv.now() - started
        local out = strip_ansi((r.stdout or "") .. (r.stderr or ""))
        -- avisos de "Deprecated" do PHP não interessam
        out = out:gsub("[^\n]*Deprecated:[^\n]*\n?", "")
        -- erro: código de saída, erro de sintaxe ou exceção (o tinker escreve "   Error  …" / "…Exception  …")
        local head = vim.trim(out):match("^[^\n]*") or ""
        local failed = r.code ~= 0 or head:find("Parse error", 1, true) ~= nil or head:match("^[%w\\]*Error%s") ~= nil
          or head:match("^[%w\\]*Exception%s") ~= nil
        pcall(require("snacks").notifier.hide, "tinker")
        local res = show(code, out, failed, ms)
        if opts.on_done then opts.on_done(res, out, failed) end
      end)
    end)
end

local function visual_selection()
  local s, e = vim.fn.getpos("v"), vim.fn.getpos(".")
  local lines = vim.fn.getregion(s, e, { type = vim.fn.mode() })
  return table.concat(lines, "\n")
end

--- Atalho: seleção (modo visual) ou a linha atual
function M.at_cursor()
  local mode = vim.fn.mode()
  local code
  if mode:match("[vV\22]") then
    code = visual_selection()
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  else
    code = vim.api.nvim_get_current_line()
  end
  -- linha de código de um método: sem o "return" e o ";" do fim
  code = code:gsub("^%s*return%s+", "")
  M.run(code)
end

local function colors()
  local ok, c = pcall(require, "config.palette")
  if not ok then return end
  local set = vim.api.nvim_set_hl
  set(0, "TinkerNormal", { fg = c.fg, bg = c.bg_float })
  set(0, "TinkerBorder", { fg = c.border, bg = c.bg_float })
  set(0, "TinkerTitle", { fg = c.fg, bg = c.bg_float, bold = true })
  set(0, "TinkerNote", { fg = c.fg_faint, bg = c.bg_float })
  set(0, "TinkerCode", { fg = c.fg_dim })
  set(0, "TinkerOut", { fg = "#DFE1E5" })
  set(0, "TinkerError", { fg = c.error })
end
colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = colors })

return M
