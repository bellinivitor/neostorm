-- Contagem de usos acima de classes, métodos e funções (Code Vision do PhpStorm):
--       3 usos
--   public function show(Shipment $shipment)
-- Vem do LSP (símbolos do arquivo + referências de cada um); atualiza ao abrir e ao salvar.
-- Para ver onde é usado: gr (lista de referências).
local M = {}

local ns = vim.api.nvim_create_namespace("usages_lens")
local FILETYPES = { php = true, javascript = true, typescript = true, vue = true, typescriptreact = true, javascriptreact = true }
local KINDS = { [5] = true, [6] = true, [12] = true } -- Class, Method, Function
local MAX = 80
local state = {} -- buf -> { tick, pending }

local function client_for(buf, method)
  for _, c in ipairs(vim.lsp.get_clients({ bufnr = buf, method = method })) do return c end
end

local function collect(symbols, out, parent, in_body)
  for _, s in ipairs(symbols or {}) do
    -- funções dentro de métodos/funções (fn() =>, closures) não entram: só as do arquivo
    if KINDS[s.kind] and #out < MAX and not (in_body and s.kind == 12) then
      local r = s.selectionRange or (s.location and s.location.range) or s.range
      if r then table.insert(out, { line = r.start.line, character = r.start.character, kind = s.kind, name = s.name, class = parent }) end
    end
    if s.children then collect(s.children, out, s.kind == 5 and s.name or parent, in_body or s.kind == 6 or s.kind == 12) end
  end
  return out
end

local function label(n)
  if n == 0 then return "sem usos" end
  return n == 1 and "1 uso" or (n .. " usos")
end

-- Rotas que apontam para classes/métodos de controller (no routes/*.php o controller é só
-- texto, então o LSP não conta como uso)
local function add_routes(buf, items)
  if vim.bo[buf].filetype ~= "php" then return end
  local name = vim.api.nvim_buf_get_name(buf)
  local root = vim.fs.root(name, { "artisan" })
  if not root or not name:find("/Controllers/", 1, true) then return end
  local ns_name
  for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, 40, false)) do
    ns_name = l:match("^namespace%s+([%w_\\]+)%s*;")
    if ns_name then break end
  end
  if not ns_name then return end
  local ok, endpoints = pcall(require, "config.endpoints")
  if not ok then return end
  for _, it in ipairs(items) do
    if it.kind == 5 then
      it.routes = endpoints.count(root, ns_name .. "\\" .. it.name)
    elseif it.kind == 6 and it.class then
      it.routes = endpoints.count(root, ns_name .. "\\" .. it.class, it.name)
    end
  end
end

local function draw(buf, items)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, it in ipairs(items) do
    if it.count then
      local text = vim.api.nvim_buf_get_lines(buf, it.line, it.line + 1, false)[1] or ""
      local indent = text:match("^%s*") or ""
      -- acima da linha da declaração (classe/método começam na linha do nome; atributos/docblock ficam acima)
      local chunks = { { indent, "" } }
      local routes = it.routes or 0
      -- só rotas (nenhum uso no código): mostra só as rotas
      if not (it.count == 0 and routes > 0) then
        table.insert(chunks, { label(it.count), (it.count == 0 and routes == 0) and "UsagesNone" or "UsagesLens" })
      end
      if routes > 0 then
        if #chunks > 1 then table.insert(chunks, { "  ", "" }) end
        table.insert(chunks, { routes == 1 and "1 rota" or (routes .. " rotas"), "UsagesRoute" })
      end
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, it.line, 0, { virt_lines = { chunks }, virt_lines_above = true })
    end
  end
end

function M.refresh(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) or not FILETYPES[vim.bo[buf].filetype] or vim.bo[buf].buftype ~= "" then return end
  local sym_client = client_for(buf, "textDocument/documentSymbol")
  local ref_client = client_for(buf, "textDocument/references")
  if not (sym_client and ref_client) then return end
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local s = state[buf] or {}
  if s.tick == tick and not s.force then return end
  s.tick, s.force = tick, nil
  state[buf] = s
  local uri = vim.uri_from_bufnr(buf)
  sym_client:request("textDocument/documentSymbol", { textDocument = { uri = uri } }, function(err, symbols)
    if err or not symbols then return end
    local items = collect(symbols, {})
    local left = #items
    if left == 0 then return vim.schedule(function() draw(buf, {}) end) end
    for _, it in ipairs(items) do
      ref_client:request("textDocument/references", {
        textDocument = { uri = uri },
        position = { line = it.line, character = it.character },
        context = { includeDeclaration = false },
      }, function(rerr, refs)
        it.count = (not rerr and refs) and #refs or nil
        left = left - 1
        if left == 0 and s.tick == tick then vim.schedule(function() pcall(add_routes, buf, items); draw(buf, items) end) end
      end, buf)
    end
  end, buf)
end

local group = vim.api.nvim_create_augroup("usages_lens", { clear = true })
vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
  group = group,
  callback = function(ev) vim.defer_fn(function() M.refresh(ev.buf) end, 200) end,
})
-- o servidor ainda está indexando o projeto logo que conecta: conta de novo depois
vim.api.nvim_create_autocmd("LspAttach", {
  group = group,
  callback = function(ev)
    for _, delay in ipairs({ 500, 4000, 12000 }) do
      vim.defer_fn(function()
        if state[ev.buf] then state[ev.buf].force = true end
        M.refresh(ev.buf)
      end, delay)
    end
  end,
})
vim.api.nvim_create_autocmd("BufWipeout", { group = group, callback = function(ev) state[ev.buf] = nil end })

local function colors()
  local ok, c = pcall(require, "config.palette")
  if not ok then return end
  vim.api.nvim_set_hl(0, "UsagesLens", { fg = c.fg_faint, italic = true })
  vim.api.nvim_set_hl(0, "UsagesNone", { fg = c.linenr, italic = true })
  vim.api.nvim_set_hl(0, "UsagesRoute", { fg = c.string, italic = true })
end
colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = colors })

return M
