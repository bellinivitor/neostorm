-- Optimize Imports (Ctrl+Option+O no PhpStorm):
--   PHP: remove os "use" sem uso do topo do arquivo e ordena os imports em ordem alfabética
--        (os "use" de traits, dentro da classe, não são tocados)
--   Vue/TS/JS: "organizar imports" do servidor de linguagem
local M = {}

local UNUSED = { P1003 = true } -- Intelephense: "Symbol ... is declared but not used"

-- linhas (0-based) com "use" de import no topo do arquivo (antes da primeira class/function/etc.)
local function top_level_use_lines(lines)
  local out = {}
  for i, l in ipairs(lines) do
    if l:match("^%s*[%a_]*%s*class%s") or l:match("^%s*interface%s") or l:match("^%s*trait%s")
      or l:match("^%s*enum%s") or l:match("^%s*abstract%s") or l:match("^%s*final%s")
      or l:match("^%s*readonly%s") or l:match("^%s*function%s") or l:match("^%s*return%s") then
      break
    end
    if l:match("^use%s") then out[i - 1] = true end
  end
  return out
end

local function sort_blocks(lines, is_use)
  -- ordena cada bloco contínuo de "use" simples (sem chaves { })
  local i = 1
  while i <= #lines do
    if is_use[i - 1] and not lines[i]:find("{", 1, true) then
      local j = i
      while j + 1 <= #lines and is_use[j] and not lines[j + 1]:find("{", 1, true) do j = j + 1 end
      local block = {}
      for k = i, j do table.insert(block, lines[k]) end
      -- classes primeiro, depois "use function" e "use const" (como o PhpStorm)
      local function rank(l)
        if l:match("^use%s+function%s") then return 2 elseif l:match("^use%s+const%s") then return 3 end
        return 1
      end
      table.sort(block, function(a, b)
        if rank(a) ~= rank(b) then return rank(a) < rank(b) end
        return a:lower() < b:lower()
      end)
      for k = i, j do lines[k] = block[k - i + 1] end
      i = j + 1
    else
      i = i + 1
    end
  end
  return lines
end

function M.php(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local is_use = top_level_use_lines(lines)
  -- imports sem uso, segundo o Intelephense
  local remove = {}
  for _, d in ipairs(vim.diagnostic.get(buf)) do
    if UNUSED[tostring(d.code)] and is_use[d.lnum] and not lines[d.lnum + 1]:find("{", 1, true) then
      remove[d.lnum] = true
    end
  end
  local out, out_is_use, removed = {}, {}, 0
  for i, l in ipairs(lines) do
    if remove[i - 1] then
      removed = removed + 1
    else
      table.insert(out, l)
      if is_use[i - 1] then out_is_use[#out - 1] = true end
    end
  end
  sort_blocks(out, out_is_use)
  if vim.deep_equal(out, lines) then
    return vim.notify("Imports já estão organizados", vim.log.levels.INFO)
  end
  -- grava só as linhas que mudaram (desfaz com um Cmd+Z)
  local view = vim.fn.winsaveview()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
  vim.fn.winrestview(view)
  vim.notify(removed > 0 and ("Imports organizados: " .. removed .. " sem uso removido(s)") or "Imports organizados",
    vim.log.levels.INFO)
end

function M.optimize()
  local ft = vim.bo.filetype
  if ft == "php" then return M.php() end
  if ft == "vue" or ft:match("^typescript") or ft:match("^javascript") then
    return vim.lsp.buf.code_action({ context = { only = { "source.organizeImports" }, diagnostics = {} }, apply = true })
  end
  vim.notify("Optimize Imports não disponível para " .. ft, vim.log.levels.INFO)
end

-- ---------------------------------------------------------------------------
-- Dobra dos imports (como no PhpStorm): o bloco de "use" do topo vira uma linha
-- só, "use ...", e já abre fechado. As outras dobras continuam vindo do treesitter.
-- ---------------------------------------------------------------------------
local cache = {} -- buf -> { tick, first, last } (linhas 1-based)

function M.block(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local c = cache[buf]
  if c and c.tick == tick then return c.first and c or nil end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local first, last
  for lnum0 in pairs(top_level_use_lines(lines)) do
    if not first or lnum0 + 1 < first then first = lnum0 + 1 end
    if not last or lnum0 + 1 > last then last = lnum0 + 1 end
  end
  -- import de várias linhas: use App\{ A, B }; termina na linha do ";"
  while last and last < #lines and not lines[last]:find(";%s*$") do last = last + 1 end
  c = { tick = tick, first = first, last = last }
  if not first or last <= first then c.first = nil end
  cache[buf] = c
  return c.first and c or nil
end

function M.foldexpr()
  local lnum = vim.v.lnum
  local b = M.block()
  if b and lnum >= b.first and lnum <= b.last then
    return lnum == b.first and ">1" or "1"
  end
  return vim.treesitter.foldexpr(lnum)
end

function M.foldtext()
  local b = M.block()
  if b and vim.v.foldstart == b.first then
    return { { "use", "@keyword.import" }, { " ", "Normal" }, { "...", "FoldImports" } }
  end
  return vim.fn.foldtext()
end

-- Liga a dobra numa janela com arquivo PHP (chamado pelo treesitter.lua)
function M.attach(win)
  vim.wo[win].foldexpr = "v:lua.require'config.imports'.foldexpr()"
  vim.wo[win].foldtext = "v:lua.require'config.imports'.foldtext()"
end

-- Fecha o bloco de imports na primeira vez que o arquivo aparece
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = vim.api.nvim_create_augroup("imports_fold", { clear = true }),
  callback = function(ev)
    if vim.bo[ev.buf].filetype ~= "php" or vim.b[ev.buf].imports_folded then return end
    local win = vim.api.nvim_get_current_win()
    vim.schedule(function()
      if not (vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == ev.buf) then return end
      local b = M.block(ev.buf)
      if not b then return end
      vim.b[ev.buf].imports_folded = true
      vim.api.nvim_win_call(win, function() pcall(vim.cmd, b.first .. "foldclose") end)
    end)
  end,
})

vim.api.nvim_create_autocmd("BufWipeout", { callback = function(ev) cache[ev.buf] = nil end })

return M
