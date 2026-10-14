return {
  "saghen/blink.cmp",
  version = "1.*",
  event = "InsertEnter",
  dependencies = { "rafamadriz/friendly-snippets" },
  opts = {
    -- Como no PhpStorm: Enter ou Tab aceitam, setas navegam, Ctrl+Espaço abre
    keymap = {
      preset = "enter",
      ["<Tab>"] = { "accept", "snippet_forward", "fallback" },
      ["<S-Tab>"] = { "snippet_backward", "fallback" },
      -- Ctrl+Espaço abre o autocomplete, como no PhpStorm do Mac (de novo: mostra/esconde a documentação)
      ["<C-Space>"] = { "show", "show_documentation", "hide_documentation" },
    },
    appearance = { nerd_font_variant = "mono" },
    completion = {
      documentation = { auto_show = true, auto_show_delay_ms = 200 },
    },
    sources = {
      default = { "lsp", "path", "snippets", "buffer" },
      -- Em PHP e Blade, sugere nomes de views, rotas, componentes, configs e envs do Laravel
      per_filetype = {
        php = { inherit_defaults = true, "blade-nav" },
        blade = { inherit_defaults = true, "blade-nav" },
      },
      providers = {
        ["blade-nav"] = { name = "blade-nav", module = "blade-nav.integrations.blink" },
      },
    },
    signature = { enabled = true },
  },
}
