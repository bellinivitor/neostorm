-- Refactor This (Ctrl+T, como no PhpStorm do Mac): refatorações de PHP pelo Phpactor.
-- Com seleção: Extract Method e Introduce Variable. Sem seleção: Rename, Introduce Constant
-- (no número/texto sob o cursor), Complete/Promote Constructor, Add Missing Properties,
-- Implement Methods, Getters/Setters, Override Method, Return Types, Import Classes e
-- Fix Class Name. O Phpactor cria com nomes padrão (newMethod, $newVariable, NEW_CONSTANT);
-- aqui o nome é pedido antes e trocado logo depois.
local M = {}

local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "Refactor" }) end

local function phpactor(buf)
  return vim.lsp.get_clients({ bufnr = buf, name = "phpactor" })[1]
end

-- offset em bytes (0-based) da linha (1-based) e coluna (0-based, em bytes)
local function offset(line, col) return vim.fn.line2byte(line) - 1 + col end

local function has_word(buf, word)
  local pat = "%f[%w_]" .. word .. "%f[^%w_]"
  for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if l:find(pat) then return true end
  end
  return false
end

-- troca o nome padrão que o Phpactor deu pelo nome escolhido
local function rename_word(buf, from, to)
  if not to or to == "" or to == from then return end
  local pat = "%f[%w_]" .. from .. "%f[^%w_]"
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, l in ipairs(lines) do
    if l:find(pat) then
      vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { (l:gsub(pat, (to:gsub("%%", "%%%%")))) })
    end
  end
end

local function exec(buf, command, args, label, after)
  local client = phpactor(buf)
  if not client then
    return notify("O Phpactor não está ativo neste arquivo (só funciona em PHP, dentro de um projeto).", vim.log.levels.WARN)
  end
  client:exec_cmd({ title = label, command = command, arguments = args }, { bufnr = buf }, function(err)
    vim.schedule(function()
      if err then return notify(label .. ": " .. (err.message or "não foi possível aplicar"), vim.log.levels.WARN) end
      if after then after() end
    end)
  end)
end

--- pede o nome, roda o comando e troca o nome padrão pelo escolhido
local function extract(buf, command, args, label, default, prompt, transform)
  if has_word(buf, default) then
    return notify("Já existe \"" .. default .. "\" neste arquivo: renomeie antes para usar o " .. label .. ".", vim.log.levels.WARN)
  end
  vim.ui.input({ prompt = prompt, default = "" }, function(name)
    if name == nil then return end
    name = vim.trim(name)
    if transform and name ~= "" then name = transform(name) end
    exec(buf, command, args, label, function() rename_word(buf, default, name) end)
  end)
end

-- propriedades da classe ({ nome = linha }), na ordem em que aparecem
local function properties(buf)
  local list = {}
  for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local visibility = l:match("^%s*public%s") or l:match("^%s*protected%s") or l:match("^%s*private%s")
    local name = visibility and not l:find("function") and not l:find("const%s") and l:match("%$([%w_]+)")
    if name then table.insert(list, { name = name, line = i }) end
  end
  return list
end

local function accessors(buf, kind)
  local props = properties(buf)
  if #props == 0 then return notify("Nenhuma propriedade nesta classe.") end
  local cur = vim.api.nvim_win_get_cursor(0)[1]
  local prefix = kind == "getter" and "get" or "set"
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  local function exists(name)
    local method = prefix .. name:sub(1, 1):upper() .. name:sub(2)
    return text:find("function%s+" .. method .. "%s*%(") ~= nil
  end
  -- cursor numa propriedade: só ela; senão, todas que ainda não têm o método
  local names = {}
  for _, p in ipairs(props) do if p.line == cur then names = { p.name } end end
  if #names == 0 then
    for _, p in ipairs(props) do if not exists(p.name) then table.insert(names, p.name) end end
  end
  if #names == 0 then return notify("Todas as propriedades já têm " .. (kind == "getter" and "getter" or "setter") .. ".") end
  local command = kind == "getter" and "generate_accessors" or "generate_mutators"
  exec(buf, command, { vim.uri_from_bufnr(buf), offset(props[1].line, 0), names },
    kind == "getter" and "Generate Getters" or "Generate Setters",
    function() notify((kind == "getter" and "Getters" or "Setters") .. " criados: " .. table.concat(names, ", ")) end)
end

local function transform(buf, name, label)
  exec(buf, "transform", { vim.uri_from_bufnr(buf), name }, label)
end

--- range = { start = {linha, col}, finish = {linha, col} } (col 0-based, fim exclusivo) ou nil
function M.open(range)
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "php" then
    -- fora do PHP, o Refactor This é só o Rename do servidor de linguagem
    return vim.lsp.buf.rename()
  end
  local uri = vim.uri_from_bufnr(buf)
  local items = {}
  local function add(label, key, run) table.insert(items, { label = label, key = key, run = run }) end

  if range then
    local s = offset(range.start[1], range.start[2])
    local e = offset(range.finish[1], range.finish[2])
    add("Extract Method…", "m", function()
      extract(buf, "extract_method", { uri, s, e }, "Extract Method", "newMethod", "Nome do método: ")
    end)
    add("Introduce Variable…", "v", function()
      extract(buf, "extract_expression", { uri, s, e }, "Introduce Variable", "newVariable", "Nome da variável: $",
        function(n) return (n:gsub("^%$", "")) end)
    end)
  else
    local pos = vim.api.nvim_win_get_cursor(0)
    add("Rename…", "r", function() vim.lsp.buf.rename() end)
    add("Introduce Constant…", "c", function()
      extract(buf, "extract_constant", { uri, offset(pos[1], pos[2]) }, "Introduce Constant", "NEW_CONSTANT", "Nome da constante: ",
        function(n) return n:upper():gsub("[^%w_]", "_") end)
    end)
    add("Complete Constructor", "k", function() transform(buf, "complete_constructor", "Complete Constructor") end)
    add("Promote Constructor Properties", "p", function() transform(buf, "promote_constructor", "Promote Constructor Properties") end)
    add("Add Missing Properties", "a", function() transform(buf, "add_missing_properties", "Add Missing Properties") end)
    add("Implement Methods", "i", function() transform(buf, "implement_contracts", "Implement Methods") end)
    add("Generate Getters", "g", function() accessors(buf, "getter") end)
    add("Generate Setters", "s", function() accessors(buf, "setter") end)
    add("Override Method…", "o", function() exec(buf, "override_method", { uri }, "Override Method") end)
    add("Add Return Types", "t", function() transform(buf, "add_missing_return_types", "Add Return Types") end)
    add("Import Missing Classes", "u", function() exec(buf, "import_all_unresolved_names", { uri }, "Import Missing Classes") end)
    add("Fix Class Name and Namespace", "n", function() transform(buf, "fix_namespace_class_name", "Fix Class Name and Namespace") end)
  end
  require("config.popup_menu").open(items, { title = "Refactor This", width = 36 })
end

--- chamado no modo visual: usa a seleção
function M.open_visual()
  local mode = vim.fn.mode()
  local a, b = vim.fn.getpos("v"), vim.fn.getpos(".")
  if a[2] > b[2] or (a[2] == b[2] and a[3] > b[3]) then a, b = b, a end
  local range
  if mode == "V" then
    local last = vim.api.nvim_buf_get_lines(0, b[2] - 1, b[2], false)[1] or ""
    range = { start = { a[2], 0 }, finish = { b[2], #last } }
  else
    local line = vim.api.nvim_buf_get_lines(0, b[2] - 1, b[2], false)[1] or ""
    -- fim inclusivo no modo visual: avança até o fim do caractere (pode ter mais de um byte)
    local char = vim.fn.strcharpart(line:sub(b[3]), 0, 1)
    range = { start = { a[2], a[3] - 1 }, finish = { b[2], b[3] - 1 + #char } }
  end
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  M.open(range)
end

return M
