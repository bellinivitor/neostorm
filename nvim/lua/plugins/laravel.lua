return {
  {
    "adalessa/laravel.nvim",
    dependencies = {
      "MunifTanjim/nui.nvim",
      "nvim-lua/plenary.nvim",
      "nvim-neotest/nvim-nio",
      "ibhagwan/fzf-lua",
    },
    cmd = { "Laravel" },
    event = { "VeryLazy" },
    opts = {},
    keys = {
      { "<leader>ll", function() Laravel.pickers.laravel() end, desc = "Laravel: picker geral" },
      { "<leader>la", function() Laravel.pickers.artisan() end, desc = "Laravel: artisan" },
      -- rotas: janela Endpoints própria (usa o PHP do projeto; a do plugin chama o php global)
      { "<leader>lr", function() require("config.endpoints").open() end, desc = "Endpoints (rotas)" },
      { "<D-M-r>", function() require("config.endpoints").open() end, mode = { "n", "i" }, desc = "Endpoints (rotas)" },
      { "<leader>lm", function() Laravel.pickers.make() end, desc = "Laravel: make" },
      { "<leader>lc", function() Laravel.pickers.commands() end, desc = "Laravel: commands" },
      { "<leader>lo", function() Laravel.pickers.resources() end, desc = "Laravel: resources" },
      { "<leader>lp", function() Laravel.commands.run("command_center") end, desc = "Laravel: command center" },
    },
  },
  {
    -- gf em view('...'), route('...') e componentes <x-...> no Blade
    "RicardoRamirezR/blade-nav.nvim",
    ft = { "blade", "php" },
    opts = {
      close_tag_on_complete = true,
      -- O autocomplete vem pelo blink.cmp (ver completion.lua), não pelo nvim-cmp
      integrations = { cmp = false, coq = false },
    },
  },
  -- (testes: ▶ na margem e painel Run, em config/tests.lua; atalhos em config/phpstorm.lua)
}
