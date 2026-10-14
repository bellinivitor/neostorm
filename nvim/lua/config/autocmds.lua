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
