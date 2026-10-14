-- Reformat Code no estilo PhpStorm. Além do formatador, mantém comentários que
-- estavam na primeira coluna (padrão do PhpStorm: "Line comment at first column").
function _G.ReformatCode()
  local buf = vim.api.nvim_get_current_buf()
  local first_col = {}
  for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if l:match("^//") or l:match("^#") then first_col[l] = true end
  end
  require("conform").format({ async = true, bufnr = buf }, function(err)
    if err or not vim.api.nvim_buf_is_valid(buf) then return end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for i, l in ipairs(lines) do
      local stripped = l:gsub("^%s+", "")
      if stripped ~= l and first_col[stripped] then
        pcall(vim.cmd, "undojoin")
        vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { stripped })
      end
    end
  end)
end

return {
  {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    cmd = "ConformInfo",
    keys = {
      -- Reformat Code: arquivo inteiro, ou só o trecho selecionado
      { "<leader>cf", function() _G.ReformatCode() end, mode = { "n", "v" }, desc = "Reformat Code" },
      -- Pint (estilo Laravel) só quando você pedir
      { "<leader>cp", function()
          local ft = vim.bo.filetype
          local f = ft == "blade" and "blade-formatter" or "pint"
          require("conform").format({ async = true, formatters = { f } })
        end, desc = "Pint / blade-formatter no arquivo" },
    },
    opts = {
      -- Como o "Reformat Code" do PhpStorm: só espaçamento, indentação e chaves.
      -- PHP usa o formatador do Intelephense (PSR-12), que não troca aspas, não
      -- reordena nem apaga imports. O Pint fica para quando você pedir (espaço c p).
      formatters_by_ft = {
        php = {},
        blade = {},
        -- Prettier só quando o projeto tem configuração de Prettier (senão usa o LSP)
        vue = { "prettierd" },
        javascript = { "prettierd" },
        typescript = { "prettierd" },
        css = { "prettierd" },
        scss = { "prettierd" },
        json = { "prettierd" },
        yaml = { "prettierd" },
        lua = { "stylua" },
      },
      default_format_opts = { lsp_format = "fallback" },
      formatters = {
        prettierd = { require_cwd = true },
        -- Usa o Pint do projeto (vendor/bin) quando existir
        pint = {
          command = function()
            local local_pint = vim.fn.getcwd() .. "/vendor/bin/pint"
            return vim.uv.fs_stat(local_pint) and local_pint or "pint"
          end,
        },
      },
      -- Sem formatar ao salvar (o PhpStorm também não formata ao salvar por padrão)
    },
  },
  {
    -- PHPStan/Larastan só roda se o projeto tiver ele no vendor
    "mfussenegger/nvim-lint",
    event = { "BufReadPost", "BufWritePost" },
    config = function()
      local lint = require("lint")
      lint.linters.phpstan.cmd = "vendor/bin/phpstan"
      lint.linters_by_ft = { php = { "phpstan" } }

      vim.api.nvim_create_autocmd("BufWritePost", {
        group = vim.api.nvim_create_augroup("vitor_lint", { clear = true }),
        pattern = "*.php",
        callback = function()
          if vim.uv.fs_stat(vim.fn.getcwd() .. "/vendor/bin/phpstan") then
            lint.try_lint()
          end
        end,
      })
    end,
  },
}
