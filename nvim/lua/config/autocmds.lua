local group = vim.api.nvim_create_augroup("vitor_config", { clear = true })

-- Front end com 2 espaços, PHP/Blade ficam com 4
vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = { "vue", "javascript", "typescript", "json", "css", "scss", "html", "lua", "yaml" },
  callback = function()
    vim.bo.shiftwidth = 2
    vim.bo.tabstop = 2
  end,
})

-- Destaca o trecho copiado
vim.api.nvim_create_autocmd("TextYankPost", {
  group = group,
  callback = function() vim.hl.on_yank({ timeout = 150 }) end,
})

-- Keymaps de LSP quando um servidor conecta no buffer
vim.api.nvim_create_autocmd("LspAttach", {
  group = group,
  callback = function(ev)
    local map = function(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { buffer = ev.buf, desc = desc })
    end
    local fzf = require("fzf-lua")
    map("gd", function()
      -- no arquivo de rotas, o nome do controller vai para o controller/método da rota
      local ok, jumped = pcall(function() return require("config.endpoints").jump_at_cursor() end)
      if ok and jumped then return end
      -- authorize('view', $x) → Policy; route('nome') → controller
      ok, jumped = pcall(function() return require("config.laravel_links").jump_at_cursor() end)
      if not (ok and jumped) then fzf.lsp_definitions() end
    end, "Ir para definição")
    map("gr", fzf.lsp_references, "Referências")
    map("gi", fzf.lsp_implementations, "Implementações")
    map("K", vim.lsp.buf.hover, "Documentação")
    map("<leader>rn", vim.lsp.buf.rename, "Renomear símbolo")
    map("<leader>ca", vim.lsp.buf.code_action, "Code action")
    map("<leader>ss", fzf.lsp_document_symbols, "Símbolos do arquivo")
    map("<leader>sS", fzf.lsp_live_workspace_symbols, "Símbolos do projeto")

    -- Inlay hints (nome dos parâmetros dentro da chamada), quando o servidor suporta
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client:supports_method("textDocument/inlayHint") then
      vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
    end
  end,
})

-- Salvar automático, como o PhpStorm:
--   depois de uma pausa na digitação, ao trocar de arquivo, ao sair da janela e ao sair do Neovim.
--   O salvamento automático não formata (o Pint roda só no Cmd+S / :w), para o código
--   não "pular" enquanto você digita.
vim.opt.autoread = true
local function autosave(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local bo = vim.bo[buf]
  if not (bo.modified and bo.modifiable and not bo.readonly and bo.buftype == "") then return end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or vim.fn.filewritable(name) == 0 and vim.fn.filereadable(name) == 1 then return end
  vim.b[buf].autosaving = true
  vim.api.nvim_buf_call(buf, function() vim.cmd("silent! lockmarks update") end)
  vim.b[buf].autosaving = false
end
_G.Autosave = autosave

local timer = vim.uv.new_timer()
vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
  group = group,
  callback = function(ev)
    timer:stop()
    -- 1,5 s sem mexer no texto
    timer:start(1500, 0, vim.schedule_wrap(function()
      -- não salva no meio de um autocomplete aberto
      if vim.fn.pumvisible() == 1 then return end
      autosave(ev.buf)
    end))
  end,
})
vim.api.nvim_create_autocmd({ "FocusLost", "BufLeave", "VimLeavePre" }, {
  group = group,
  callback = function(ev)
    if ev.event == "FocusLost" or ev.event == "VimLeavePre" then
      for _, b in ipairs(vim.api.nvim_list_bufs()) do autosave(b) end
    else
      autosave(ev.buf)
    end
  end,
})

-- Recarrega arquivos alterados fora do editor (git checkout, artisan make...)
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter" }, {
  group = group,
  command = "silent! checktime",
})

-- Coluna de código nova divide o espaço igualmente com as colunas de código vizinhas.
-- Painéis (Projeto, Claude, Terminal, barra lateral) mantêm a largura que já tinham.
local function is_code_win(w)
  if not vim.api.nvim_win_is_valid(w) or vim.api.nvim_win_get_config(w).relative ~= "" then return false end
  if require("config.panels").is_panel(w) then return false end
  local b = vim.api.nvim_win_get_buf(w)
  local ft = vim.bo[b].filetype
  return vim.bo[b].buftype == "" and ft ~= "neo-tree" and ft ~= "aerial" and ft ~= "activity_bar"
end

-- a "linha" do layout (colunas lado a lado) em que a janela está
local function row_of(win)
  local function find(node, parent)
    if node[1] == "leaf" then return node[2] == win and parent or nil end
    for _, child in ipairs(node[2]) do
      local r = find(child, node)
      if r then return r end
    end
  end
  local row = find(vim.fn.winlayout(), nil)
  return row and row[1] == "row" and row or nil
end

local function equalize_columns(win)
  local row = row_of(win)
  if not row then return end
  local cols = {}
  for _, child in ipairs(row[2]) do
    if child[1] == "leaf" and is_code_win(child[2]) then table.insert(cols, child[2]) end
  end
  if #cols < 2 then return end
  local total = 0
  for _, w in ipairs(cols) do total = total + vim.api.nvim_win_get_width(w) end
  local each = math.floor(total / #cols)
  for i = 1, #cols - 1 do pcall(vim.api.nvim_win_set_width, cols[i], each) end
end

local known = {}
vim.api.nvim_create_autocmd("WinNew", {
  group = group,
  callback = function()
    -- espera a janela ficar pronta (buffer e marca de painel) antes de decidir
    vim.schedule(function()
      local new = {}
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if not known[w] then table.insert(new, w); known[w] = true end
      end
      for _, w in ipairs(new) do
        if is_code_win(w) then return equalize_columns(w) end
      end
    end)
  end,
})
vim.api.nvim_create_autocmd("WinClosed", {
  group = group,
  callback = function(ev) known[tonumber(ev.match)] = nil end,
})

-- Toda janela normal ganha o tom de ilha (a cor padrão, Normal, é o fundo escuro).
-- Janelas que já mapeiam Normal (painéis, barra lateral, Projeto) ficam como estão;
-- as que trocam o winhighlight sem Normal (diff, plugins) recebem Island na frente.
local function island(w)
  if not vim.api.nvim_win_is_valid(w) or vim.api.nvim_win_get_config(w).relative ~= "" then return end
  local whl = vim.wo[w].winhighlight
  if ("," .. whl):find(",Normal:", 1, true) then return end
  vim.wo[w].winhighlight = "Normal:Island,NormalNC:Island" .. (whl ~= "" and ("," .. whl) or "")
end
vim.api.nvim_create_autocmd({ "VimEnter", "WinNew", "WinEnter", "BufWinEnter" }, {
  group = group,
  callback = function()
    vim.schedule(function()
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do island(w) end
    end)
  end,
})
vim.api.nvim_create_autocmd("OptionSet", {
  group = group,
  pattern = "winhighlight",
  callback = function()
    local w = vim.api.nvim_get_current_win()
    vim.schedule(function() island(w) end)
  end,
})
