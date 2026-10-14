-- Links do Laravel que o LSP não entende (são só texto para ele):
--   $this->authorize('view', $shipment)   → ShipmentPolicy@view      (Cmd+clique, Cmd+B, gd)
--   Gate::authorize('syncTracking')        → Gate::define('syncTracking', …)
--   route('attachments.download', $a)      → controller da rota, e a URL no fim da linha
local M = {}

local hint_ns = vim.api.nvim_create_namespace("route_name_hints")
M.hint_ns = hint_ns

local function read_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and lines or {}
end

-- "use" do arquivo: nome curto → classe completa; e o namespace
local function imports(lines)
  local map, ns_name = {}, nil
  for _, l in ipairs(lines) do
    ns_name = ns_name or l:match("^namespace%s+([%w_\\]+)%s*;")
    local fq, alias = l:match("^use%s+([%w_\\]+)%s+as%s+([%w_]+)%s*;")
    if fq then map[alias] = fq else
      local u = l:match("^use%s+([%w_\\]+)%s*;")
      if u then map[u:match("([^\\]+)$")] = u end
    end
  end
  return map, ns_name
end

local function full_name(name, map, ns_name)
  if name:sub(1, 1) == "\\" then return name:sub(2) end
  local first = name:match("^([^\\]+)")
  if map[first] then return map[first] .. name:sub(#first + 1) end
  return (ns_name and (ns_name .. "\\") or "") .. name
end

local function open_at(file, line)
  vim.cmd("normal! m'") -- Cmd+[ volta para cá
  vim.cmd.edit(vim.fn.fnameescape(file))
  pcall(vim.api.nvim_win_set_cursor, 0, { line or 1, 0 })
  vim.cmd("normal! zz")
  return true
end

-- ---------------------------------------------------------------------------
-- Policies
-- ---------------------------------------------------------------------------
-- model → policy, pelo $policies do AuthServiceProvider; e os Gate::define
local function policy_map(root)
  local file = root .. "/app/Providers/AuthServiceProvider.php"
  local lines = read_lines(file)
  local map, ns_name = imports(lines)
  local policies, gates = {}, {}
  for i, l in ipairs(lines) do
    local m, p = l:match("([%w_\\]+)::class%s*=>%s*([%w_\\]+)::class")
    if m then policies[full_name(m, map, ns_name)] = full_name(p, map, ns_name) end
    local ms, ps = l:match("['\"]([%w_\\]+)['\"]%s*=>%s*['\"]([%w_\\]+)['\"]")
    if ms then policies[(ms:gsub("^\\", ""))] = (ps:gsub("^\\", "")) end
    local g = l:match("Gate::define%(%s*['\"]([%w_%-%.]+)['\"]")
    if g then gates[g] = { file = file, line = i } end
  end
  return policies, gates
end

-- tipo de uma variável no arquivo: parâmetro "Shipment $shipment", "@var Shipment", "$x = new Shipment"
local function var_type(lines, var, cursor)
  for i = cursor, 1, -1 do
    local l = lines[i] or ""
    local t = l:match("([%w_\\]+)%s+%$" .. var .. "[%s,%)=]") or l:match("@var%s+([%w_\\]+)%s+%$" .. var)
      or l:match("%$" .. var .. "%s*=%s*new%s+([%w_\\]+)") or l:match("%$" .. var .. "%s*=%s*([%w_\\]+)::")
    -- (ignora palavras do PHP: "foreach ($lista as $shipment)" não diz o tipo)
    local skip = { ["?"] = 1, int = 1, string = 1, array = 1, bool = 1, float = 1, mixed = 1, as = 1, ["return"] = 1,
      new = 1, echo = 1, print = 1, yield = 1, use = 1, global = 1, fn = 1, ["function"] = 1, ["and"] = 1, ["or"] = 1 }
    if t and not skip[t] then
      return t
    end
  end
  return var:sub(1, 1):upper() .. var:sub(2) -- $shipment → Shipment
end

local function policy_jump(root, text, col, lines, cursor_line)
  -- authorize/can/cannot/allows/denies('ability', X::class | $model)
  local ability, rest = nil, nil
  for s, fn, a, r in text:gmatch("()([%w_]+)%(%s*['\"]([%w_%-%.]+)['\"]%s*,?%s*([^%)]*)") do
    if ({ authorize = 1, can = 1, cannot = 1, allows = 1, denies = 1, check = 1, any = 1, authorizeResource = 1, cant = 1 })[fn] then
      ability, rest = a, r
      if col >= s then break end
    end
  end
  if not ability then return false end
  local policies, gates = policy_map(root)
  local map, ns_name = imports(lines)
  local model
  local cls = rest and rest:match("([%w_\\]+)::class")
  if cls then
    model = full_name(cls, map, ns_name)
  else
    local var = rest and rest:match("^%$([%w_]+)")
    if var and var ~= "this" then model = full_name(var_type(lines, var, cursor_line), map, ns_name) end
  end
  local endpoints = require("config.endpoints")
  local function try_model(m)
    local policy = policies[m]
    if not policy then
      -- convenção do Laravel: App\Models\Shipment → App\Policies\ShipmentPolicy
      local short = m:match("([^\\]+)$")
      for mm, p in pairs(policies) do if mm:match("([^\\]+)$") == short then policy = p; break end end
      policy = policy or ("App\\Policies\\" .. short .. "Policy")
    end
    local file, line = endpoints.find_method(root, policy, ability)
    if file then return open_at(file, line) end
  end
  if model and try_model(model) then return true end
  -- o tipo achado não levou a uma Policy: tenta pelo nome da variável ($shipment → Shipment)
  local var = rest and rest:match("^%$([%w_]+)")
  if var and var ~= "this" and try_model(var:sub(1, 1):upper() .. var:sub(2)) then return true end
  -- sem model: é um Gate::define
  local g = gates[ability]
  if g then return open_at(g.file, g.line) end
  return false
end

-- ---------------------------------------------------------------------------
-- route('nome')
-- ---------------------------------------------------------------------------
local function route_by_name(root, name)
  for _, rt in ipairs(require("config.endpoints").load(root) or {}) do
    if rt.name == name then return rt end
  end
end

-- nome da rota na linha (o mais perto do cursor quando houver mais de um)
local function route_name_at(text, col)
  local best
  for s, name in text:gmatch("()route%(%s*['\"]([%w_%.%-]+)['\"]") do
    if not best or col >= s then best = name end
  end
  return best
end

local function route_jump(root, text, col)
  local name = route_name_at(text, col)
  if not name then return false end
  local rt = route_by_name(root, name)
  if not rt then return false end
  local class, method = rt.action:match("^(.-)@(.+)$")
  class, method = class or rt.action, method or "__invoke"
  local endpoints = require("config.endpoints")
  local file, line, cfile, cline = endpoints.find_method(root, class, method)
  file, line = file or cfile, line or cline
  if file then return open_at(file, line) end
  return false
end

--- Cmd+clique / Cmd+B / gd: tenta Policy e route('nome'); devolve true se pulou
function M.jump_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  local root = vim.fs.root(name, { "artisan" })
  if not root or name:find(root .. "/routes/", 1, true) then return false end
  local text = vim.api.nvim_get_current_line()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local col = cursor[2] + 1
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  -- o que está mais perto do cursor: route(...) ou authorize(...)
  local r_at = text:find("route%(%s*['\"]")
  local p_at = text:find("authorize%(") or text:find("can%(") or text:find("allows%(") or text:find("denies%(")
  if r_at and (not p_at or math.abs(col - r_at) <= math.abs(col - p_at)) then
    return route_jump(root, text, col) or policy_jump(root, text, col, lines, cursor[1])
  end
  return policy_jump(root, text, col, lines, cursor[1]) or (r_at ~= nil and route_jump(root, text, col))
end

-- ---------------------------------------------------------------------------
-- URL das route('nome') no fim da linha
-- ---------------------------------------------------------------------------
function M.annotate(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local name = vim.api.nvim_buf_get_name(buf)
  local root = vim.fs.root(name, { "artisan" })
  if not root or name:find(root .. "/routes/", 1, true) then return end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local any = false
  for _, l in ipairs(lines) do if l:find("route%(") then any = true; break end end
  vim.api.nvim_buf_clear_namespace(buf, hint_ns, 0, -1)
  if not any then return end -- sem route(): nem carrega a lista de rotas
  local app = nil
  for i, l in ipairs(lines) do
    for rname in l:gmatch("route%(%s*['\"]([%w_%.%-]+)['\"]") do
      local rt = route_by_name(root, rname)
      if rt then
        if not app then
          for _, e in ipairs(read_lines(root .. "/.env")) do
            app = app or e:match("^APP_URL%s*=%s*['\"]?([^'\"%s]+)")
          end
          app = (app or ""):gsub("/+$", "")
        end
        local scheme = app:match("^(%a+)://") or "https"
        local url = (rt.domain and (scheme .. "://" .. rt.domain) or app) .. rt.uri
        local verb = rt.method:match("^(%a+)") or ""
        pcall(vim.api.nvim_buf_set_extmark, buf, hint_ns, i - 1, 0, {
          virt_text = { { "  \u{2192} " .. verb .. " " .. url, "RouteTarget" } }, virt_text_pos = "eol",
        })
      end
    end
  end
end

local timer
vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
  group = vim.api.nvim_create_augroup("route_name_hints", { clear = true }),
  pattern = { "*.php" },
  callback = function(ev)
    if timer then timer:stop() end
    timer = vim.defer_fn(function() pcall(M.annotate, ev.buf) end, 200)
  end,
})

return M
