-- Branch main (reescrita do nvim-treesitter): requer o tree-sitter CLI instalado
local parsers = {
  "php", "phpdoc", "blade", "html", "css", "scss",
  "javascript", "typescript", "tsx", "vue",
  "json", "yaml", "lua", "luadoc", "vim", "vimdoc",
  "markdown", "markdown_inline", "bash", "sql", "dockerfile",
  "gitcommit", "diff", "query",
}

return {
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
  lazy = false,
  build = ":TSUpdate",
  config = function()
    require("nvim-treesitter").install(parsers)

    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("vitor_treesitter", { clear = true }),
      callback = function(ev)
        local lang = vim.treesitter.language.get_lang(ev.match)
        if not lang or not pcall(vim.treesitter.start, ev.buf, lang) then return end
        vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        -- O FileType dispara de novo quando o LSP carrega; reaplicar as opções de dobra
        -- reabria todas as dobras (inclusive os imports recém-fechados). Só aplica uma vez.
        local expr = ev.match == "php" and "v:lua.require'config.imports'.foldexpr()" or "v:lua.vim.treesitter.foldexpr()"
        if vim.wo.foldmethod ~= "expr" or vim.wo.foldexpr ~= expr then
          vim.wo.foldexpr = expr
          vim.wo.foldmethod = "expr"
          vim.wo.foldlevel = 99
          -- PHP: o bloco de imports vira uma dobra só ("use ..."), fechada ao abrir
          if ev.match == "php" then require("config.imports").attach(vim.api.nvim_get_current_win()) end
        end
      end,
    })
  end,
}
