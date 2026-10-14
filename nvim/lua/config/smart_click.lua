-- Cmd+clique do PhpStorm:
--   clicou num uso       -> vai para a declaração
--   clicou na declaração -> lista onde está sendo usado
-- Em __invoke e __construct o Intelephense não liga $acao(...) ao método,
-- então nesses casos procuramos os usos da classe.
local M = {}

local CLASS_KINDS = { [5] = true, [10] = true, [11] = true, [23] = true } -- Class, Enum, Interface, Struct
local MAGIC = { __invoke = true, __construct = true }

local function to_list(r)
  if not r then return {} end
  if not vim.islist(r) then return { r } end
  return r
end

local function same_line_as_declaration(results, buf, cursor)
  local has_def, on_decl = false, false
  for _, res in pairs(results) do
    for _, loc in ipairs(to_list(res.result)) do
      has_def = true
      local uri = loc.targetUri or loc.uri
      local range = loc.targetSelectionRange or loc.range
      if uri and range and vim.uri_to_bufnr(uri) == buf and range.start.line == cursor[1] - 1 then
        on_decl = true
      end
    end
  end
  return has_def, on_decl
end

-- Classe que contém a linha do cursor (via document symbols)
local function enclosing_class(symbols, line)
  local found
  local function walk(list)
    for _, s in ipairs(list or {}) do
      local range = s.range or (s.location and s.location.range)
      if range and range.start.line <= line and range["end"].line >= line then
        if CLASS_KINDS[s.kind] then found = s end
        walk(s.children)
      end
    end
  end
  walk(symbols)
  return found
end

local function references_at(client, buf, position)
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(buf),
    position = position,
    context = { includeDeclaration = false },
  }
  local res = client:request_sync("textDocument/references", params, 8000, buf)
  return (res and res.result) or {}
end

local function show(locations, encoding, title)
  -- Remove duplicados
  local seen, unique = {}, {}
  for _, loc in ipairs(locations) do
    local key = loc.uri .. ":" .. loc.range.start.line .. ":" .. loc.range.start.character
    if not seen[key] then seen[key] = true; table.insert(unique, loc) end
  end
  M.found = unique
  if M.dry_run then return end
  if #unique == 0 then
    vim.notify("Nenhum uso encontrado", vim.log.levels.INFO)
  elseif #unique == 1 then
    vim.lsp.util.show_document(unique[1], encoding, { focus = true })
  else
    vim.fn.setqflist({}, " ", { title = title, items = vim.lsp.util.locations_to_items(unique, encoding) })
    require("fzf-lua").quickfix()
  end
end

function M.find_usages()
  local buf = vim.api.nvim_get_current_buf()
  local client = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/references" })[1]
  if not client then return end
  local enc = client.offset_encoding
  local word = vim.fn.expand("<cword>")
  local cursor = vim.api.nvim_win_get_cursor(0)
  local pos = vim.lsp.util.make_position_params(0, enc).position

  local locations = references_at(client, buf, pos)
  local title = "Usos de " .. word

  if MAGIC[word] or #locations == 0 then
    local sym = client:request_sync("textDocument/documentSymbol",
      { textDocument = vim.lsp.util.make_text_document_params(buf) }, 8000, buf)
    local class = sym and sym.result and enclosing_class(sym.result, cursor[1] - 1)
    if class then
      local sel = class.selectionRange or class.range or class.location.range
      vim.list_extend(locations, references_at(client, buf, sel.start))
      title = "Usos de " .. class.name
    end
  end
  show(locations, enc, title)
end

function M.go(opts)
  -- no arquivo de rotas, o nome do controller vai para o controller/método da rota
  -- (não no dry_run, que só verifica se há destino)
  if not (opts and opts.dry_run) then
    -- no terminal (Run, Terminal): caminho:linha de stack traces e testes
    if vim.bo.buftype == "terminal" then
      pcall(function() require("config.stack_links").open_at_cursor() end)
      return
    end
    local ok, jumped = pcall(function() return require("config.endpoints").jump_at_cursor() end)
    if ok and jumped then return end
    -- authorize('view', $x) → Policy; route('nome') → controller (config/laravel_links.lua)
    ok, jumped = pcall(function() return require("config.laravel_links").jump_at_cursor() end)
    if ok and jumped then return end
  end
  opts = opts or {}
  M.dry_run = opts.dry_run
  local buf = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/definition" })
  if #clients == 0 then
    vim.notify("Nenhum servidor de linguagem ativo neste arquivo (veja :Mason e :checkhealth vim.lsp)", vim.log.levels.WARN)
    return
  end

  local params = vim.lsp.util.make_position_params(0, clients[1].offset_encoding)
  vim.lsp.buf_request_all(buf, "textDocument/definition", params, function(results)
    vim.schedule(function()
      local cursor = vim.api.nvim_win_get_cursor(0)
      local has_def, on_decl = same_line_as_declaration(results, buf, cursor)
      M.last = (on_decl or not has_def) and "references" or "definition"
      if M.last == "references" then
        M.find_usages()
      elseif not M.dry_run then
        vim.lsp.buf.definition()
      end
    end)
  end)
end

-- Botão apertado: só move o cursor para onde o mouse clicou
function M.press()
  M.pending = false
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or pos.line == 0 then return end
  vim.api.nvim_set_current_win(pos.winid)
  vim.api.nvim_win_set_cursor(pos.winid, { pos.line, math.max(pos.column - 1, 0) })
  if vim.fn.mode() ~= "n" then vim.cmd.stopinsert() end
  M.pending = true
end

-- Botão solto: agora sim vai para a declaração ou lista os usos
function M.release()
  if not M.pending then return end
  M.pending = false
  vim.schedule(M.go)
end

-- Compatibilidade: clique completo de uma vez
function M.click()
  M.press()
  M.release()
end

return M
