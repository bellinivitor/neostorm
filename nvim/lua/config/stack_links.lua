-- Caminhos de arquivo clicáveis nos painéis de terminal (Run, Terminal):
--   app/Models/Shipment.php:120 · #0 /…/Shipment.php(120): … · at tests/Unit/X.php:8 · in /…/x.php on line 12
-- Cmd+clique, gf ou Enter (fora do modo de digitação) abrem o arquivo na linha, na janela de código.
local M = {}

local EXT = "php|js|ts|tsx|jsx|vue|json|blade%.php|lua|css|scss|env|yml|yaml|xml|md|py|rb|go|sh"

-- todos os "arquivo + linha" da linha de texto: { { path, line, s, e } }
local function find_all(text)
  local out = {}
  local function add(path, line, s, e)
    if path and path:match("%.%a+$") then table.insert(out, { path = path, line = tonumber(line) or 1, s = s, e = e }) end
  end
  -- caminho(:linha) ou caminho(linha)
  for s, path, sep, line, e in text:gmatch("()([%w_%./%-~]+%.%a+)([:%(])(%d+)%)?()") do
    add(path, line, s, e)
  end
  -- "in /x/y.php on line 12"
  for s, path, line, e in text:gmatch("()([%w_%./%-~]+%.%a+) on line (%d+)()") do add(path, line, s, e) end
  return out
end

local function resolve(path, root)
  path = path:gsub("^~", vim.env.HOME or "~")
  if path:sub(1, 1) == "/" then return vim.uv.fs_stat(path) and path or nil end
  for _, base in ipairs({ root, vim.fn.getcwd() }) do
    local full = base .. "/" .. path:gsub("^%./", "")
    if vim.uv.fs_stat(full) then return full end
  end
end

--- Link no texto da linha `line` (coluna col, 1-based, opcional); abre e devolve true
function M.open_at(buf, line, col)
  local text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
  local links = find_all(text)
  if #links == 0 then return false end
  -- o link sob o cursor; senão o primeiro da linha que existir
  local pick
  for _, l in ipairs(links) do
    if col and col >= l.s and col <= l.e then pick = l; break end
  end
  local root = vim.fn.getcwd()
  local candidates = pick and { pick } or links
  for _, l in ipairs(candidates) do
    local file = resolve(l.path, root)
    if file then
      local main = require("config.panels").main_win()
      if main then vim.api.nvim_set_current_win(main) else vim.cmd("wincmd p") end
      vim.cmd.edit(vim.fn.fnameescape(file))
      pcall(vim.api.nvim_win_set_cursor, 0, { l.line, 0 })
      vim.cmd("normal! zz")
      return true
    end
  end
  return false
end

--- Usado pelo Cmd+clique (smart_click) e pelo gf/Enter: cursor atual
function M.open_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "terminal" then return false end
  local pos = vim.api.nvim_win_get_cursor(0)
  return M.open_at(buf, pos[1], pos[2] + 1)
end

--- Teclas e sublinhado numa janela de painel de terminal
function M.attach(win, buf)
  if buf and vim.api.nvim_buf_is_valid(buf) and not vim.b[buf].stack_links then
    vim.b[buf].stack_links = true
    for _, lhs in ipairs({ "gf", "<CR>" }) do
      vim.keymap.set("n", lhs, function()
        if not M.open_at_cursor() and lhs == "gf" then vim.notify("Nenhum arquivo nesta linha", vim.log.levels.INFO) end
      end, { buffer = buf, desc = "Abrir arquivo:linha" })
    end
  end
  if win and vim.api.nvim_win_is_valid(win) and not vim.w[win].stack_links_match then
    -- sublinhado discreto em caminho:linha (regex do Vim, só nesta janela)
    vim.w[win].stack_links_match = vim.api.nvim_win_call(win, function()
      return vim.fn.matchadd("TermFileLink", [[\v[[:alnum:]_./~-]+\.(]] .. EXT:gsub("%%", "\\") .. [[)(:\d+|\(\d+\)| on line \d+)]], 5)
    end)
  end
end

vim.api.nvim_set_hl(0, "TermFileLink", { underline = true, sp = "#7A7F89" })
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function() vim.api.nvim_set_hl(0, "TermFileLink", { underline = true, sp = "#7A7F89" }) end,
})

return M
