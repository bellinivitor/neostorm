-- PHP de cada projeto, como o Herd serve o site ("herd isolate"):
-- ex.: o site roda em PHP 8.0 (fixado no Herd), mas o `php` do terminal é o global (8.5).
-- Aqui descobrimos o PHP do projeto (herd which-php) e criamos uma pasta com um `php`
-- apontando para ele, que vai na frente do PATH dos terminais do Neovim (Terminal, Run,
-- Claude). Assim `php artisan`, `composer` e os testes usam a versão certa.
local M = {}

local cache = {}
local SHIMS = vim.fn.stdpath("cache") .. "/php-shims"

--- Caminho do PHP do projeto (cwd por padrão); nil se o Herd não souber
function M.bin(root)
  root = root or vim.fn.getcwd()
  if cache[root] ~= nil then return cache[root] or nil end
  local ok, r = pcall(function()
    return vim.system({ "herd", "which-php" }, { cwd = root, text = true }):wait(3000)
  end)
  local path = ok and r and r.code == 0 and vim.trim(r.stdout or ""):match("[^\n]+$") or nil
  if path and vim.uv.fs_stat(path) then cache[root] = path else cache[root] = false end
  return cache[root] or nil
end

--- "8.0" a partir do nome do executável do Herd (php80 → 8.0); nil para o PHP global
function M.version(root)
  local bin = M.bin(root)
  local major, minor = (bin and vim.fn.fnamemodify(bin, ":t") or ""):match("^php(%d)(%d+)$")
  return major and (major .. "." .. minor) or nil
end

-- Pasta com um `php` (link para o PHP do projeto)
local function shim_dir(bin)
  local name = vim.fn.fnamemodify(bin, ":t")
  local dir = SHIMS .. "/" .. name
  local link = dir .. "/php"
  if not vim.uv.fs_stat(link) then
    vim.fn.mkdir(dir, "p")
    vim.uv.fs_symlink(bin, link)
  end
  return dir
end

--- Variáveis para um terminal do projeto: o PATH com o PHP do projeto na frente
--- (só quando o projeto usa uma versão diferente da global)
function M.env(root, env)
  env = env and vim.deepcopy(env) or {}
  local bin = M.bin(root)
  if bin and M.version(root) then
    env.PATH = shim_dir(bin) .. ":" .. (env.PATH or vim.env.PATH or "")
  end
  -- sem nada para mudar: nil (o jobstart recusa uma tabela vazia com "E475: Invalid argument: env")
  return next(env) and env or nil
end

return M
