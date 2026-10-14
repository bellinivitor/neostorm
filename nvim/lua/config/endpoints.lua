-- Endpoints (como a janela de rotas do PhpStorm): todas as rotas do Laravel numa lista,
-- busca por URL, nome ou controller, e Enter abre o método do controller.
--   GET     api/v1/shipments/{id}          shipments.show   ShipmentController@show
-- As rotas vêm do `php artisan route:list --json`, com o PHP do projeto (Herd).
local M = {}

local ns = vim.api.nvim_create_namespace("endpoints")
local st = {}
local cache = {} -- root -> { routes, at }

local METHOD_HL = {
  GET = "EndpointsGet", HEAD = "EndpointsGet", POST = "EndpointsPost", PUT = "EndpointsPut",
  PATCH = "EndpointsPut", DELETE = "EndpointsDelete", ANY = "EndpointsAny",
}

local function root()
  local r = vim.fs.root(0, { "artisan" }) or vim.fs.root(vim.fn.getcwd(), { "artisan" })
  return r
end

-- "App\Http\Controllers\X@show" → "XController@show" curto (só o nome da classe)
local function short_action(action)
  if not action or action == "" then return "" end
  if action == "Closure" then return "função anônima" end
  local class, method = action:match("^(.-)@(.+)$")
  class = class or action
  local name = class:match("([^\\]+)$") or class
  return method and (name .. "@" .. method) or name
end

local function load(r, force)
  if not force and cache[r] then return cache[r] end
  local php = require("config.project_php").bin(r) or "php"
  local res = vim.system({ php, "-d", "error_reporting=0", "-d", "display_errors=0", "artisan", "route:list", "--json" },
    { cwd = r, text = true }):wait(30000)
  local out = res.stdout or ""
  local ok, data = pcall(vim.json.decode, out:sub((out:find("[", 1, true) or 1)), { luanil = { object = true, array = true } })
  if not ok or type(data) ~= "table" then
    return nil, vim.trim((res.stderr or "") .. (res.stdout or "")):sub(1, 400)
  end
  local routes = {}
  for _, rt in ipairs(data) do
    local methods = vim.tbl_filter(function(m) return m ~= "HEAD" end, vim.split(rt.method or "", "|", { plain = true }))
    -- PUT|PATCH vira PUT (o Laravel registra os dois juntos); muitos métodos vira ANY
    local method = #methods > 2 and "ANY" or (table.concat(methods, "|") == "PUT|PATCH" and "PUT" or table.concat(methods, "|"))
    local uri = rt.uri or ""
    if uri:sub(1, 1) ~= "/" then uri = "/" .. uri end
    table.insert(routes, {
      method = method, uri = uri, name = rt.name or "", action = rt.action or "",
      short = short_action(rt.action), search = (method .. " " .. uri .. " " .. (rt.name or "") .. " " .. (rt.action or "")):lower(),
      main = (uri .. " " .. (rt.name or "")):lower(), -- URL e nome: pesam mais na ordem da busca
      domain = rt.domain ~= "" and rt.domain or nil, middleware = rt.middleware or {},
    })
  end
  cache[r] = routes
  return routes
end

--- Rotas do projeto (lidas uma vez e guardadas); usado também pela contagem de usos
function M.routes(r) return (load(r)) end

--- Quantas rotas apontam para a classe (method = nil) ou para um método dela
function M.count(r, class, method)
  local routes = load(r)
  if not routes then return 0 end
  local n = 0
  for _, rt in ipairs(routes) do
    local c, m = rt.action:match("^(.-)@(.+)$")
    c, m = c or rt.action, m or "__invoke" -- controller de uma ação só: __invoke
    if c == class and (not method or m == method) then n = n + 1 end
  end
  return n
end

-- ---------------------------------------------------------------------------
-- Abrir o controller no método (PSR-4 do composer.json)
-- ---------------------------------------------------------------------------
-- Mapa PSR-4 do projeto e dos pacotes do vendor (vendor/composer/installed.json):
-- { { prefix, dir }, ... } do prefixo mais longo para o mais curto
local psr4_cache = {}
local function psr4(r)
  if psr4_cache[r] then return psr4_cache[r] end
  local list = {}
  local function add(map, base)
    for prefix, dirs in pairs(map or {}) do
      for _, d in ipairs(type(dirs) == "table" and dirs or { dirs }) do
        table.insert(list, { prefix = prefix, dir = base .. "/" .. d:gsub("/$", "") })
      end
    end
  end
  local function read(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local ok, data = pcall(vim.json.decode, f:read("*a"))
    f:close()
    return ok and data or nil
  end
  local composer = read(r .. "/composer.json") or {}
  add((composer.autoload or {})["psr-4"], r)
  local installed = read(r .. "/vendor/composer/installed.json")
  local packages = installed and (installed.packages or installed) or {}
  for _, pkg in ipairs(packages) do
    if pkg["install-path"] then
      add((pkg.autoload or {})["psr-4"], vim.fs.normalize(r .. "/vendor/composer/" .. pkg["install-path"]))
    end
  end
  table.sort(list, function(x, y) return #x.prefix > #y.prefix end)
  psr4_cache[r] = list
  return list
end

local function class_file(r, class)
  class = class:gsub("^\\", "")
  for _, e in ipairs(psr4(r)) do
    if class:sub(1, #e.prefix) == e.prefix then
      local path = e.dir .. "/" .. class:sub(#e.prefix + 1):gsub("\\", "/") .. ".php"
      if vim.uv.fs_stat(path) then return path end
    end
  end
end

-- Procura o método na classe e, se não estiver nela, nos traits e na classe pai
-- (ex.: login() do LoginController vem do trait AuthenticatesUsers, no vendor)
local function find_method(r, class, method, depth)
  depth = depth or 0
  local file = class_file(r, class)
  if not file then return nil end
  local lines = vim.fn.readfile(file)
  local ns_name, uses, class_line, parent, traits = nil, {}, nil, nil, {}
  for i, l in ipairs(lines) do
    if method and l:match("function%s+" .. vim.pesc(method) .. "%s*%(") then return file, i end
    ns_name = ns_name or l:match("^namespace%s+([%w_\\]+)%s*;")
    if not class_line then
      local fq, alias = l:match("^use%s+([%w_\\]+)%s+as%s+([%w_]+)%s*;")
      if fq then uses[alias] = fq else
        local u = l:match("^use%s+([%w_\\]+)%s*;")
        if u then uses[u:match("([^\\]+)$")] = u end
      end
      if l:match("^%s*[%w%s]*class%s+[%w_]+") or l:match("^%s*trait%s+[%w_]+") then
        class_line = i
        parent = l:match("extends%s+([%w_\\]+)")
      end
    else
      local t = l:match("^%s*use%s+([%w_\\,%s]+);")
      if t then for name in t:gmatch("[%w_\\]+") do table.insert(traits, name) end end
    end
  end
  if not method then return file, class_line or 1 end
  if depth < 4 then
    local function full(name)
      if name:sub(1, 1) == "\\" then return name:sub(2) end
      return uses[name] or ((ns_name and (ns_name .. "\\") or "") .. name)
    end
    for _, t in ipairs(traits) do
      local f, l = find_method(r, full(t), method, depth + 1)
      if f then return f, l end
    end
    if parent then
      local f, l = find_method(r, full(parent), method, depth + 1)
      if f then return f, l end
    end
  end
  return nil, nil, file, class_line
end

local function open_route(rt, r)
  if rt.action == "Closure" or rt.action == "" then
    return vim.notify("A rota " .. rt.uri .. " é uma função anônima: veja em routes/", vim.log.levels.INFO, { title = "Endpoints" })
  end
  local class, method = rt.action:match("^(.-)@(.+)$")
  class = class or rt.action
  method = method or "__invoke"
  -- o método pode estar num trait ou na classe pai (find_method procura lá também)
  local file, line, cfile, cline = find_method(r, class, method)
  file, line = file or cfile, line or cline or 1
  if not file then
    return vim.notify("Não achei o arquivo de " .. class, vim.log.levels.WARN, { title = "Endpoints" })
  end
  local main = require("config.panels").main_win()
  if main then vim.api.nvim_set_current_win(main) end
  vim.cmd.edit(vim.fn.fnameescape(file))
  pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
  vim.cmd("normal! zz")
end

-- ---------------------------------------------------------------------------
-- Ir do arquivo de rotas para o controller (Cmd+clique, Cmd+B, gd)
--   Route::post('airlines-restore', 'AirlineRestoreController');   → __invoke
--   Route::get('x', 'XController@show') / [XController::class, 'show'] → show
--   Route::resource('airlines', 'AirlineController');              → a classe
-- O nome no arquivo de rotas é só texto (o LSP não acha); o route:list diz qual classe é.
-- ---------------------------------------------------------------------------
local function jump_to(r, class, method)
  local file, line, class_file_path, class_line = find_method(r, class, method)
  -- método não achado: abre a classe na linha "class"
  file, line = file or class_file_path, line or class_line or 1
  if not file then return false end
  vim.cmd("normal! m'") -- Cmd+[ volta para cá
  vim.cmd.edit(vim.fn.fnameescape(file))
  pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
  vim.cmd("normal! zz")
  return true
end

-- "use" do arquivo: nome curto → classe completa (inclui "use A\B\{C, D as E};")
local function imports(buf)
  local src = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  local map = {}
  local function add(fq, alias)
    fq = vim.trim(fq):gsub("^\\", "")
    if fq == "" then return end
    map[alias or fq:match("([^\\]+)$")] = fq
  end
  for body in src:gmatch("\n%s*use%s+([^;]+);") do
    local prefix, group = body:match("^(.-)\\?{(.*)}%s*$")
    for _, part in ipairs(prefix and vim.split(group, ",", { plain = true }) or { body }) do
      local item = vim.trim(part)
      local fq, alias = item:match("^(.-)%s+as%s+([%w_]+)$")
      fq = fq or item
      if item ~= "" then add(prefix and (vim.trim(prefix):gsub("\\$", "") .. "\\" .. fq) or fq, alias) end
    end
  end
  return map
end

-- rotas indexadas pelo nome curto do controller (para resolver centenas de linhas rápido)
local index_cache = setmetatable({}, { __mode = "k" })
local function by_short(routes)
  if index_cache[routes] then return index_cache[routes] end
  local idx = {}
  for _, rt in ipairs(routes) do
    local c, m = rt.action:match("^(.-)@(.+)$")
    c, m = c or rt.action, m or "__invoke"
    local short = c:match("([^\\]+)$") or c
    idx[short] = idx[short] or {}
    table.insert(idx[short], { rt = rt, class = c, method = m })
  end
  index_cache[routes] = idx
  return idx
end

-- Descobre o controller (e o método) de uma linha do arquivo de rotas.
-- ctx = { imports, ns } (ns: namespace mais usado no arquivo, para desempatar)
-- Devolve { class, method, resource = bool, methods = {…} } ou nil
local function resolve(routes, text, ctx)
  -- (o nome pode vir com o caminho completo: [\App\Http\...\X::class, 'index'])
  local short, method = text:match("([%w_\\]+)::class%s*,%s*['\"]([%w_]+)['\"]")
  local class_form = short ~= nil
  if not short then
    local cls, m = text:match("['\"]([%w_\\]+Controller)@([%w_]+)['\"]")
    short, method = cls, m
  end
  if not short then short = text:match("['\"]([%w_\\]+Controller)['\"]") end
  if not short then return nil end
  local verb, uri = text:match("Route::(%a+)%(%s*['\"]([^'\"]*)['\"]")
  verb = verb and verb:lower() or ""
  local plain = short:gsub("^\\", "")
  -- pelo "use" do arquivo (ou caminho completo na linha), a classe é exata
  -- (em texto, 'Auth\LoginController' é relativo ao namespace do grupo; completo só com \ no
  -- começo ou no formato X::class)
  local absolute = short:sub(1, 1) == "\\" or (class_form and plain:find("\\", 1, true))
  local exact = (ctx.imports or {})[short] or (absolute and plain or nil)
  local tail = plain:match("([^\\]+)$")
  local is_resource = verb == "resource" or verb == "apiresource"
  local uri_norm = uri and ("/" .. uri:gsub("^/", "")) or nil
  local best, best_score
  for _, cand in ipairs(by_short(routes)[tail] or {}) do
    local c, m, rt = cand.class, cand.method, cand.rt
    local same_class = (exact and c == exact) or (not exact and ("\\" .. c):sub(-#plain - 1) == "\\" .. plain)
    if same_class and (not method or m == method) then
      -- mesma URL (o arquivo tem um prefixo de grupo, então compara o fim), mesmo verbo, mesmo namespace
      local same_uri = uri_norm and (rt.uri == uri_norm or rt.uri:sub(-#uri_norm) == uri_norm
        or (is_resource and rt.uri:find(uri_norm, 1, true) ~= nil))
      local same_verb = is_resource or verb == "" or verb == "any" or verb == "match" or rt.method:lower():find(verb, 1, true) ~= nil
      local same_ns = ctx.ns and c:sub(1, #ctx.ns + 1) == ctx.ns .. "\\"
      local score = (same_ns and 4 or 0) + (same_uri and 2 or 0) + (same_verb and 1 or 0)
      if not best_score or score > best_score then best, best_score = cand, score end
    end
  end
  if not best then return nil end
  local out = { class = best.class, method = best.method, resource = is_resource and not method, score = best_score, exact = exact ~= nil, rt = best.rt }
  if out.resource then
    -- ações do resource (respeita ->only(...)/->except(...), que o route:list já aplicou)
    out.methods, out.method = {}, nil
    local seen = {}
    for _, cand in ipairs(by_short(routes)[tail] or {}) do
      if cand.class == best.class and uri_norm and cand.rt.uri:find(uri_norm, 1, true) and not seen[cand.method] then
        seen[cand.method] = true
        table.insert(out.methods, cand.method)
      end
    end
  end
  return out
end

local ns_cache = {}
-- namespace mais usado pelas rotas do arquivo (as que resolvem sem dúvida)
local function file_ns(buf, routes, imp)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local c = ns_cache[buf]
  if c and c.tick == tick then return c.ns end
  local count = {}
  for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local res = l:find("Route::", 1, true) and resolve(routes, l, { imports = imp })
    if res and (res.exact or res.score >= 3) then
      local n = res.class:match("^(.*)\\[^\\]+$")
      if n then count[n] = (count[n] or 0) + 1 end
    end
  end
  local best, n = nil, 0
  for k, v in pairs(count) do if v > n then best, n = k, v end end
  ns_cache[buf] = { tick = tick, ns = best }
  return best
end

local function route_file(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local r = vim.fs.root(name, { "artisan" })
  if r and name:find(r .. "/routes/", 1, true) then return r end
end

local function context(buf, routes)
  local imp = imports(buf)
  return { imports = imp, ns = file_ns(buf, routes, imp) }
end

function M.jump_at_cursor(line)
  local buf = vim.api.nvim_get_current_buf()
  local r = route_file(buf)
  if not r then return false end
  local routes = load(r)
  if not routes then return false end
  local text = line and vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or vim.api.nvim_get_current_line()
  local res = resolve(routes, text, context(buf, routes))
  if not res then return false end
  return jump_to(r, res.class, res.method)
end

-- ---------------------------------------------------------------------------
-- No arquivo de rotas: destino no fim de cada linha e ícone clicável na margem
--   Route::get('chart/{chart}', 'ChartController');      → ChartController@__invoke
-- ---------------------------------------------------------------------------
local hint_ns = vim.api.nvim_create_namespace("route_targets")
M.hint_ns = hint_ns

function M.annotate(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local r = route_file(buf)
  if not r then return end
  local routes = load(r)
  if not routes then return end
  local ctx = context(buf, routes)
  vim.api.nvim_buf_clear_namespace(buf, hint_ns, 0, -1)
  for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if l:find("Route::", 1, true) and not l:match("^%s*//") then
      local res = resolve(routes, l, ctx)
      if res then
        local short = res.class:match("([^\\]+)$")
        local label = res.resource and (short .. "  " .. table.concat(res.methods, ", ")) or (short .. "@" .. res.method)
        pcall(vim.api.nvim_buf_set_extmark, buf, hint_ns, i - 1, 0, {
          virt_text = { { "  \u{2192} " .. label, "RouteTarget" } }, virt_text_pos = "eol",
          sign_text = "\u{EA94}", sign_hl_group = "RouteTargetSign", priority = 40,
        })
      end
    end
  end
end

-- clique no ícone da margem (chamado pela coluna da esquerda, config/gitgutter.lua)
function _G.RouteGutterClick()
  local pos = vim.fn.getmousepos()
  vim.schedule(function()
    if pos.winid == 0 then return end
    vim.api.nvim_set_current_win(pos.winid)
    M.jump_at_cursor(pos.line)
  end)
end

local hint_timer
vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "TextChanged", "InsertLeave" }, {
  group = vim.api.nvim_create_augroup("route_targets", { clear = true }),
  pattern = "*/routes/*.php",
  callback = function(ev)
    if hint_timer then hint_timer:stop() end
    hint_timer = vim.defer_fn(function() pcall(M.annotate, ev.buf) end, 150)
  end,
})

-- ---------------------------------------------------------------------------
-- Popup (mesmo visual do Run Anything)
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

local function render()
  if not (st.list_buf and vim.api.nvim_buf_is_valid(st.list_buf)) then return end
  local query = (vim.api.nvim_buf_get_lines(st.input_buf, 0, 1, false)[1] or ""):lower()
  local words = vim.split(query, "%s+", { trimempty = true })
  local items = {}
  for idx, rt in ipairs(st.routes) do
    local ok, score = true, 0
    for _, w in ipairs(words) do
      if not rt.search:find(w, 1, true) then ok = false; break end
      if rt.main:find(w, 1, true) then score = score + 1 end
    end
    if ok then table.insert(items, { rt = rt, score = score, idx = idx }) end
  end
  -- primeiro as rotas em que as palavras aparecem na URL ou no nome; sem busca, a ordem do Laravel
  table.sort(items, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if #words > 0 and #a.rt.uri ~= #b.rt.uri then return #a.rt.uri < #b.rt.uri end -- URL mais curta = rota mais direta
    return a.idx < b.idx
  end)
  for i, it in ipairs(items) do items[i] = it.rt end
  st.items = items
  local width = st.width
  local text, marks = {}, {}
  local MW = 7
  for i, rt in ipairs(items) do
    local method = rt.method:sub(1, MW)
    local right = (rt.name ~= "" and (rt.name .. "  ") or "") .. rt.short
    local left = "  " .. method .. string.rep(" ", MW - #method) .. "  "
    local room = width - vim.fn.strdisplaywidth(left) - 2
    local uri = rt.uri
    local right_room = room - vim.fn.strdisplaywidth(uri) - 3
    if right_room < 12 then
      uri = vim.fn.strcharpart(uri, 0, math.max(10, room - 16)) .. "…"
      right_room = room - vim.fn.strdisplaywidth(uri) - 3
    end
    if vim.fn.strdisplaywidth(right) > right_room then right = "…" .. vim.fn.strcharpart(right, vim.fn.strchars(right) - right_room + 1) end
    local line = left .. uri
    line = line .. string.rep(" ", math.max(2, width - vim.fn.strdisplaywidth(line) - vim.fn.strdisplaywidth(right) - 1)) .. right
    table.insert(text, line)
    local first = method:match("^[A-Z]+") or method
    table.insert(marks, { i - 1, 2, 2 + #method, METHOD_HL[first] or "EndpointsAny" })
    table.insert(marks, { i - 1, #left, #left + #uri, "EndpointsUri" })
    table.insert(marks, { i - 1, #line - #right, #line, "EndpointsHint" })
  end
  if #text == 0 then
    text = { "", "   Nenhuma rota encontrada" }
    table.insert(marks, { 1, 0, -1, "EndpointsHint" })
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
  vim.api.nvim_win_set_config(st.input_win, {
    title = { { " Endpoints ", "EndpointsTitle" }, { #items .. " de " .. #st.routes .. " ", "EndpointsHint" } }, title_pos = "left",
  })
  select(st.sel or 1)
end

local function activate(i)
  local rt = st.items and st.items[i or st.sel]
  if not rt then return end
  local r = st.root
  close()
  vim.schedule(function() open_route(rt, r) end)
end

function M.open(opts)
  opts = opts or {}
  if st.input_win and vim.api.nvim_win_is_valid(st.input_win) then return close() end
  local r = root()
  if not r then return vim.notify("Esta pasta não é um projeto Laravel (sem artisan)", vim.log.levels.WARN, { title = "Endpoints" }) end
  local routes, err = load(r, opts.refresh)
  if not routes then
    return vim.notify("Não consegui ler as rotas (php artisan route:list):\n" .. (err or ""), vim.log.levels.ERROR, { title = "Endpoints" })
  end
  st = { root = r, routes = routes, prev_win = vim.api.nvim_get_current_win() }
  st.width = math.min(130, vim.o.columns - 8)
  local height = math.max(8, math.floor(vim.o.lines * 0.6))
  local col = math.floor((vim.o.columns - st.width) / 2)
  local row = math.max(2, math.floor(vim.o.lines * 0.12))

  st.input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[st.input_buf].bufhidden = "wipe"
  vim.b[st.input_buf].completion = false
  st.input_win = vim.api.nvim_open_win(st.input_buf, true, {
    relative = "editor", row = row, col = col, width = st.width, height = 1,
    style = "minimal", border = { "╭", "─", "╮", "│", "", "", "", "│" }, zindex = 210,
    title = " Endpoints ", title_pos = "left",
  })
  vim.wo[st.input_win].winhighlight = "Normal:EndpointsNormal,FloatBorder:EndpointsBorder"
  st.list_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[st.list_buf].bufhidden = "wipe"
  st.list_win = vim.api.nvim_open_win(st.list_buf, false, {
    relative = "editor", row = row + 2, col = col, width = st.width, height = height,
    style = "minimal", border = { "├", "─", "┤", "│", "╯", "─", "╰", "│" }, zindex = 210,
  })
  vim.wo[st.list_win].cursorline = true
  vim.wo[st.list_win].winhighlight = "Normal:EndpointsNormal,FloatBorder:EndpointsBorder,CursorLine:EndpointsSel"

  local ibuf = st.input_buf
  local icon_ns = vim.api.nvim_create_namespace("endpoints_icon")
  vim.api.nvim_buf_set_extmark(ibuf, icon_ns, 0, 0, {
    virt_text = { { " \u{F0349}  ", "EndpointsHint" } }, virt_text_pos = "inline", right_gravity = false,
  })
  local ph = vim.api.nvim_create_namespace("endpoints_placeholder")
  local function placeholder()
    vim.api.nvim_buf_clear_namespace(ibuf, ph, 0, -1)
    if (vim.api.nvim_buf_get_lines(ibuf, 0, 1, false)[1] or "") == "" then
      vim.api.nvim_buf_set_extmark(ibuf, ph, 0, 0, { virt_text = { { "URL, nome da rota ou controller", "EndpointsHint" } }, virt_text_pos = "overlay" })
    end
    vim.api.nvim_buf_set_extmark(ibuf, ph, 0, 0, { virt_text = { { "Enter abre o controller  ⌃E exemplo  ⌃R recarrega ", "EndpointsHint" } }, virt_text_pos = "right_align" })
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
  imap("<PageDown>", function() select((st.sel or 1) + 15) end)
  imap("<PageUp>", function() select((st.sel or 1) - 15) end)
  imap("<CR>", function() activate() end)
  imap("<Esc>", close)
  imap("<C-r>", function() close(); M.open({ refresh = true }) end)
  -- Ctrl+E: exemplo de requisição da rota selecionada
  imap("<C-e>", function()
    local rt, r = st.items and st.items[st.sel], st.root
    if not rt then return end
    close()
    vim.schedule(function() require("config.route_example").show(rt, r) end)
  end)
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

local function colors()
  local ok, c = pcall(require, "config.palette")
  if not ok then return end
  local set = vim.api.nvim_set_hl
  set(0, "EndpointsNormal", { fg = c.fg, bg = c.bg_float })
  set(0, "EndpointsBorder", { fg = c.border, bg = c.bg_float })
  set(0, "EndpointsTitle", { fg = c.fg, bg = c.bg_float, bold = true })
  set(0, "EndpointsSel", { bg = "#2E436E" })
  set(0, "EndpointsHint", { fg = c.fg_faint })
  set(0, "EndpointsUri", { fg = c.fg })
  set(0, "EndpointsGet", { fg = c.hint, bold = true })
  set(0, "EndpointsPost", { fg = c.method, bold = true })
  set(0, "EndpointsPut", { fg = c.warn, bold = true })
  set(0, "EndpointsDelete", { fg = c.error, bold = true })
  set(0, "EndpointsAny", { fg = c.variable, bold = true })
  set(0, "RouteTarget", { fg = c.fg_faint, italic = true })
  set(0, "RouteTargetSign", { fg = c.method })
end
colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = colors })


-- ---------------------------------------------------------------------------
-- Para outros módulos (exemplo de requisição: config/route_example.lua)
-- ---------------------------------------------------------------------------
M.load = load
M.class_file = class_file
M.find_method = find_method
M.root = root

--- Rota da linha do arquivo de rotas (a resolvida pelo salto/anotação), ou nil
function M.route_at_line(buf, line)
  local r = route_file(buf)
  if not r then return nil end
  local routes = load(r)
  if not routes then return nil end
  local text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
  local res = resolve(routes, text, context(buf, routes))
  if not res then return nil end
  -- resource: todas as ações da linha (quem chamar escolhe)
  local list = { res.rt }
  if res.resource then
    list = {}
    local uri = text:match("Route::%a+%(%s*['\"]([^'\"]*)['\"]") or ""
    local uri_norm = "/" .. uri:gsub("^/", "")
    for _, rt in ipairs(routes) do
      local c = rt.action:match("^(.-)@") or rt.action
      if c == res.class and rt.uri:find(uri_norm, 1, true) then table.insert(list, rt) end
    end
  end
  return list, r
end

--- Rotas que apontam para class@method
function M.routes_for(r, class, method)
  local out = {}
  for _, rt in ipairs(load(r) or {}) do
    local c, m = rt.action:match("^(.-)@(.+)$")
    c, m = c or rt.action, m or "__invoke"
    if c == class and m == method then table.insert(out, rt) end
  end
  return out
end

return M
