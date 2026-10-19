-- Exemplo de consumo de uma rota (Cmd+Option+E): URL completa (APP_URL do .env ou o domínio
-- da rota), método, cabeçalhos e um payload de exemplo montado das regras de validação
-- (FormRequest::rules() ou $request->validate([...]) no método).
--   POST https://app.test/api/airlines
--   { "code": "ABCD", "name": "Texto de exemplo", "country_id": 1, "airline_status": 0 }
-- y copia como curl, Y copia como requisição HTTP, q fecha.
-- Funciona numa linha de routes/*.php, dentro de um método de controller e no popup de Endpoints.
local M = {}

local ns = vim.api.nvim_create_namespace("route_example")

local function read_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and lines or {}
end

local function env_value(root, key)
  for _, l in ipairs(read_lines(root .. "/.env")) do
    local v = l:match("^" .. key .. "%s*=%s*(.-)%s*$")
    if v then return (v:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")) end
  end
end

-- ---------------------------------------------------------------------------
-- URL
-- ---------------------------------------------------------------------------
local function example_param(name)
  name = name:gsub("%?$", "")
  if name:match("uuid") then return "9f8b3c2e-1a2b-4c3d-8e9f-0a1b2c3d4e5f" end
  if name:match("slug") then return "exemplo" end
  return "1"
end

local function full_url(root, rt)
  local app = env_value(root, "APP_URL") or "http://localhost"
  local scheme = app:match("^(%a+)://") or "https"
  local base = rt.domain and (scheme .. "://" .. rt.domain) or app:gsub("/+$", "")
  local path = rt.uri:gsub("{([%w_%?]+)}", function(p) return example_param(p) end)
  return base .. path, rt.uri:find("{", 1, true) ~= nil
end

-- ---------------------------------------------------------------------------
-- Payload a partir das regras de validação
-- ---------------------------------------------------------------------------
-- "use" do arquivo: nome curto → classe completa
local function file_imports(lines)
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

-- Entradas 'campo' => regras de um trecho de código (string 'a|b' ou lista [...] em várias linhas)
local function parse_rules(lines, from, to)
  local rules, order = {}, {}
  local i = from
  while i <= to do
    local l = lines[i]
    local key, rest = l:match("^%s*['\"]([^'\"]+)['\"]%s*=>%s*(.*)$")
    if key then
      local text = rest
      -- lista que continua nas próximas linhas: junta até fechar o ]
      if text:match("^%[") then
        local depth = select(2, text:gsub("%[", "")) - select(2, text:gsub("%]", ""))
        while depth > 0 and i < to do
          i = i + 1
          text = text .. " " .. lines[i]
          depth = select(2, text:gsub("%[", "")) - select(2, text:gsub("%]", ""))
        end
      end
      local tokens = {}
      for q in text:gmatch("['\"]([^'\"]*)['\"]") do
        for part in q:gmatch("[^|]+") do table.insert(tokens, vim.trim(part)) end
      end
      if text:find("Rule::in%(") then
        local first = text:match("Rule::in%(%s*%[%s*['\"]?([^'\",%]]+)")
        if first then table.insert(tokens, "in:" .. first) end
      end
      if text:find("Rule::enum%(") or text:find("new Enum%(") then table.insert(tokens, "enum") end
      if not rules[key] then table.insert(order, key) end
      rules[key] = tokens
    end
    i = i + 1
  end
  return rules, order
end

-- Valor de exemplo pelo tipo das regras e pelo nome do campo
local function example_value(key, tokens)
  local set, param = {}, {}
  for _, t in ipairs(tokens) do
    local name, arg = t:match("^([%w_]+):?(.*)$")
    if name then set[name] = true; param[name] = arg end
  end
  local leaf = key:match("([^.]+)$") or key
  if set["in"] and param["in"] ~= "" then
    local first = param["in"]:match("^([^,]+)")
    return tonumber(first) or first
  end
  if set.boolean or set.accepted then return true end
  if leaf:match("ids$") then return { __list = true, __item = 1 } end
  if set.array then return {} end
  if set.integer or set.numeric or set.digits or leaf:match("_id$") or leaf == "id" then
    if set.numeric and not set.integer then return 10.5 end
    return 1
  end
  if set.email or leaf:match("email") then return "usuario@exemplo.com" end
  if set.date or set.date_format or leaf:match("_at$") or leaf:match("date") then return "2026-10-13" end
  if set.url or leaf:match("url") then return "https://exemplo.com" end
  if set.uuid then return "9f8b3c2e-1a2b-4c3d-8e9f-0a1b2c3d4e5f" end
  if set.file or set.image or set.mimes then return "(arquivo)" end
  if leaf:match("password") then return "senha-secreta" end
  if leaf:match("phone") or leaf:match("telefone") then return "+55 11 99999-0000" end
  if leaf:match("cpf") then return "123.456.789-09" end
  if leaf:match("cnpj") then return "12.345.678/0001-90" end
  if leaf:match("zip") or leaf:match("cep") then return "01310-100" end
  if leaf:match("code") or leaf:match("codigo") then
    local max = tonumber(param.max or "")
    return ("ABCDEFGHIJ"):sub(1, math.min(max or 4, 10))
  end
  if leaf:match("name") or leaf:match("nome") then return "Nome de exemplo" end
  return "texto"
end

-- Monta o objeto (mantendo a ordem) com campos aninhados: a.b e itens.*.qty
local function build_payload(rules, order)
  local root = { __order = {} }
  local function child(node, k, is_list)
    if node[k] == nil then
      node[k] = is_list and { __list = true, __order = {} } or { __order = {} }
      table.insert(node.__order, k)
    end
    return node[k]
  end
  for _, key in ipairs(order) do
    local parts = vim.split(key, ".", { plain = true })
    local node = root
    for i, part in ipairs(parts) do
      local last = i == #parts
      local next_is_star = parts[i + 1] == "*"
      if part == "*" then
        -- item de lista: usa (ou cria) o primeiro item
        if last then
          node.__item = example_value(key, rules[key])
        else
          node.__item = type(node.__item) == "table" and node.__item or { __order = {} }
          node = node.__item
        end
      elseif last then
        -- uma lista declarada antes (a.* ) não é sobrescrita pelo "array" do pai
        if node[part] == nil then table.insert(node.__order, part) end
        if type(node[part]) ~= "table" then node[part] = example_value(key, rules[key]) end
      else
        node = child(node, part, next_is_star)
      end
    end
  end
  return root
end

local function encode(v, indent)
  indent = indent or ""
  local inner = indent .. "  "
  if type(v) == "table" then
    if v.__list or (v.__order == nil and vim.islist(v)) then
      local item = v.__item
      if item == nil then return "[]" end
      return "[\n" .. inner .. encode(item, inner) .. "\n" .. indent .. "]"
    end
    local order = v.__order or {}
    if #order == 0 then return v.__list and "[]" or "{}" end
    local parts = {}
    for _, k in ipairs(order) do table.insert(parts, inner .. vim.json.encode(k) .. ": " .. encode(v[k], inner)) end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
  end
  return vim.json.encode(v)
end

-- Regras do método: FormRequest tipado nos parâmetros ou $request->validate([...]) no corpo
local function rules_for(root, rt)
  local endpoints = require("config.endpoints")
  local class, method = rt.action:match("^(.-)@(.+)$")
  class, method = class or rt.action, method or "__invoke"
  local file, line = endpoints.find_method(root, class, method)
  if not file or not line then return nil end
  local lines = read_lines(file)
  local imports, ns_name = file_imports(lines)
  -- assinatura (pode ocupar várias linhas)
  local sig, j = "", line
  repeat sig = sig .. " " .. (lines[j] or ""); j = j + 1 until sig:find("%)") or j > line + 8
  for typ in sig:gmatch("([%w_\\]+)%s+%$[%w_]+") do
    if typ:match("Request$") and typ ~= "Request" then
      local fq = typ:sub(1, 1) == "\\" and typ:sub(2) or imports[typ] or ((ns_name and ns_name .. "\\" or "") .. typ)
      local rfile = endpoints.class_file(root, fq)
      if rfile then
        local rl = read_lines(rfile)
        for i, l in ipairs(rl) do
          if l:match("function%s+rules%s*%(") then
            local depth, k = 0, i
            repeat
              local cur = rl[k] or ""
              depth = depth + select(2, cur:gsub("{", "")) - select(2, cur:gsub("}", ""))
              k = k + 1
            until (depth <= 0 and k > i + 1) or k > #rl
            local rules, order = parse_rules(rl, i, k - 1)
            return rules, order, "das regras de " .. typ
          end
        end
      end
    end
  end
  -- validação inline no corpo do método
  local depth, k, started = 0, line, false
  repeat
    local cur = lines[k] or ""
    if cur:find("{") then started = true end
    depth = depth + select(2, cur:gsub("{", "")) - select(2, cur:gsub("}", ""))
    k = k + 1
  until (started and depth <= 0) or k > #lines
  for i = line, k - 1 do
    if (lines[i] or ""):find("validate%(") then
      local rules, order = parse_rules(lines, i, k - 1)
      if #order > 0 then return rules, order, "das regras do $request->validate()" end
    end
  end
  -- sem regras: os campos que o método lê do request ($request->input('x'), $request->x…)
  local NOT_FIELDS = {
    user = true, all = true, only = true, except = true, validate = true, validated = true, route = true,
    file = true, ip = true, header = true, headers = true, merge = true, method = true, url = true,
    fullUrl = true, path = true, wantsJson = true, expectsJson = true, ajax = true, isMethod = true,
    query = true, input = true, get = true, post = true, filled = true, has = true, boolean = true,
    integer = true, string = true, collect = true, toArray = true, session = true, cookie = true, bearerToken = true,
  }
  local rules, order = {}, {}
  local function add(name, tokens)
    if not rules[name] then table.insert(order, name) end
    rules[name] = rules[name] and #rules[name] > 0 and rules[name] or tokens
  end
  for i = line, k - 1 do
    local l = lines[i] or ""
    for fn, name in l:gmatch("%$request%->([%a]+)%(%s*['\"]([%w_.]+)['\"]") do
      if fn == "boolean" then add(name, { "boolean" })
      elseif fn == "integer" then add(name, { "integer" })
      elseif fn ~= "file" and fn ~= "header" and fn ~= "route" and fn ~= "cookie" then add(name, {}) end
    end
    for name in l:gmatch("%$request%->([%a_][%w_]*)") do
      local after = l:match("%$request%->" .. name .. "(.?)")
      if not NOT_FIELDS[name] and after ~= "(" then add(name, {}) end
    end
  end
  if #order > 0 then return rules, order, "dos campos que o método lê ($request->…); confira os tipos" end
end

-- ---------------------------------------------------------------------------
-- Popup
-- ---------------------------------------------------------------------------
local function needs_login(rt)
  for _, m in ipairs(rt.middleware or {}) do
    if m:match("Authenticate") or m:match("^auth") then return m:match("([^\\]+)$") end
  end
end

function M.show(rt, root)
  local url, had_params = full_url(root, rt)
  local verb = (rt.method:match("^(%a+)") or "GET"):gsub("ANY", "GET")
  local rules, order, source = rules_for(root, rt)
  local has_body = order and #order > 0 and verb ~= "GET" and verb ~= "DELETE"
  local body = has_body and encode(build_payload(rules, order)) or nil
  -- GET com regras: vira query string de exemplo
  if order and #order > 0 and (verb == "GET" or verb == "DELETE") then
    local q = {}
    for _, k in ipairs(order) do
      if not k:find("[%.%*]") then
        local v = example_value(k, rules[k])
        if type(v) ~= "table" then table.insert(q, k .. "=" .. vim.uri_encode(tostring(v))) end
      end
    end
    if #q > 0 then url = url .. "?" .. table.concat(q, "&") end
  end

  local text, marks = {}, {}
  local function add(line, hl) table.insert(text, line); if hl then table.insert(marks, { #text - 1, 0, -1, hl }) end end
  add(" " .. verb .. " " .. url)
  table.insert(marks, { 0, 1, 1 + #verb, "RouteExVerb" })
  table.insert(marks, { 0, 2 + #verb, -1, "RouteExUrl" })
  add(" Accept: application/json", "RouteExHeader")
  if body then add(" Content-Type: application/json", "RouteExHeader") end
  if body then
    add("")
    for _, l in ipairs(vim.split(body, "\n", { plain = true })) do
      table.insert(text, " " .. l)
      local r = #text - 1
      local ks, ke = l:find('^%s*"[^"]*"')
      if ks then table.insert(marks, { r, ks, ke + 1, "RouteExKey" }) end
      local vs = l:find(":%s*", 1)
      if vs and ks then table.insert(marks, { r, vs + 1, -1, "RouteExValue" }) end
    end
  end
  add("")
  local short = (rt.action:match("([^\\]+)$") or rt.action)
  add(" " .. (rt.name ~= "" and (rt.name .. "  ") or "") .. short, "RouteExNote")
  local login = needs_login(rt)
  if login then add(" Precisa de login (" .. login .. "): no navegador já vai com o cookie da sessão", "RouteExWarn") end
  if had_params then add(" Parâmetros da URL preenchidos com valores de exemplo", "RouteExNote") end
  if source then
    add(" Payload montado " .. source, "RouteExNote")
  elseif verb ~= "GET" then
    add(" Sem regras de validação encontradas para montar o payload", "RouteExNote")
  end

  -- textos para copiar
  local curl = { "curl -X " .. verb .. " " .. vim.fn.shellescape(url), "  -H 'Accept: application/json'" }
  if body then
    table.insert(curl, "  -H 'Content-Type: application/json'")
    -- (compacta o texto formatado, para manter a ordem dos campos)
    local compact = body:gsub("\n%s*", ""):gsub('": ', '":')
    table.insert(curl, "  -d " .. vim.fn.shellescape(compact))
  end
  local curl_text = table.concat(curl, " \\\n")
  local http = verb .. " " .. url .. "\nAccept: application/json" .. (body and ("\nContent-Type: application/json\n\n" .. body) or "")

  local width = 0
  for _, l in ipairs(text) do width = math.max(width, vim.fn.strdisplaywidth(l)) end
  width = math.min(math.max(width + 2, 60), vim.o.columns - 8)
  local height = math.min(#text, vim.o.lines - 6)
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
    relative = "editor", row = math.max(1, math.floor((vim.o.lines - height) / 2) - 2), col = math.floor((vim.o.columns - width) / 2),
    width = width, height = height, style = "minimal", border = "rounded", zindex = 220,
    title = { { " Exemplo de requisição ", "RouteExTitle" } }, title_pos = "left",
    footer = { { " y copia como curl   Y copia como HTTP   q fecha ", "RouteExNote" } }, footer_pos = "right",
  })
  vim.wo[win].winhighlight = "Normal:RouteExNormal,FloatBorder:RouteExBorder"
  vim.wo[win].wrap = false
  local function close() if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end end
  local function copy(s, what)
    vim.fn.setreg("+", s)
    vim.notify("Copiado como " .. what, vim.log.levels.INFO, { title = "Exemplo de requisição" })
  end
  local function map(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true }) end
  map("q", close)
  map("<Esc>", close)
  map("y", function() copy(curl_text, "curl") end)
  map("Y", function() copy(http, "requisição HTTP") end)
  vim.api.nvim_create_autocmd("WinLeave", { buffer = buf, once = true, callback = function() vim.schedule(close) end })
  return { text = text, curl = curl_text, http = http }
end

-- escolhe entre várias rotas (resource, ou a mesma ação em mais de uma URL)
local function pick(list, root, cb)
  if #list == 1 then return cb(list[1]) end
  vim.ui.select(list, {
    prompt = "Qual rota?",
    format_item = function(rt) return (rt.method .. string.rep(" ", 7 - #rt.method)) .. rt.uri .. "  " .. (rt.action:match("@(.+)$") or "") end,
  }, function(choice) if choice then cb(choice) end end)
end

--- Atalho: rota da linha (routes/*.php) ou do método do controller sob o cursor
function M.at_cursor()
  local endpoints = require("config.endpoints")
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local list, root = endpoints.route_at_line(buf, line)
  if not list then
    -- dentro de um controller: o método sob o cursor
    local name = vim.api.nvim_buf_get_name(buf)
    root = vim.fs.root(name, { "artisan" })
    if not root then return vim.notify("Não é um projeto Laravel", vim.log.levels.WARN, { title = "Exemplo de requisição" }) end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local _, ns_name = file_imports(lines)
    local class
    for _, l in ipairs(lines) do class = class or l:match("^%s*[%w%s]*class%s+([%w_]+)") end
    local method
    for i = line, 1, -1 do
      method = lines[i]:match("function%s+([%w_]+)%s*%(")
      if method then break end
    end
    if class and method and ns_name then list = endpoints.routes_for(root, ns_name .. "\\" .. class, method) end
    if not list or #list == 0 then
      return vim.notify("Nenhuma rota aponta para este método (ou não é uma linha de rota)", vim.log.levels.INFO, { title = "Exemplo de requisição" })
    end
  end
  pick(list, root, function(rt) M.show(rt, root) end)
end

local function colors()
  local ok, c = pcall(require, "config.palette")
  if not ok then return end
  local set = vim.api.nvim_set_hl
  set(0, "RouteExNormal", { fg = c.fg, bg = c.bg_float })
  set(0, "RouteExBorder", { fg = c.border, bg = c.bg_float })
  set(0, "RouteExTitle", { fg = c.fg, bg = c.bg_float, bold = true })
  set(0, "RouteExVerb", { fg = c.hint, bold = true })
  set(0, "RouteExUrl", { fg = require("config.palette").bright })
  set(0, "RouteExHeader", { fg = c.fg_dim })
  set(0, "RouteExKey", { fg = c.field })
  set(0, "RouteExValue", { fg = c.string })
  set(0, "RouteExNote", { fg = c.fg_faint })
  set(0, "RouteExWarn", { fg = c.warn })
end
colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = colors })

return M
