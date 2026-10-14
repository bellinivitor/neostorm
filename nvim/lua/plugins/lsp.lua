return {
  {
    -- Carrega no início: o setup coloca a pasta bin do Mason no PATH,
    -- senão o Neovim não acha o intelephense e os outros servidores
    "mason-org/mason.nvim",
    lazy = false,
    opts = {},
  },
  {
    -- Também no início: ele instala o que falta no VimEnter (com VeryLazy o momento já tinha passado)
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    lazy = false,
    dependencies = { "mason-org/mason.nvim" },
    init = function()
      -- Quando terminar de instalar, conecta os servidores nos arquivos já abertos (sem reiniciar)
      vim.api.nvim_create_autocmd("User", {
        pattern = "MasonToolsUpdateCompleted",
        callback = function()
          vim.schedule(function() vim.cmd("silent! doautoall FileType") end)
        end,
      })
    end,
    opts = {
      run_on_start = true,
      start_delay = 0,
      ensure_installed = {
        -- LSPs
        "intelephense", "vtsls", "vue-language-server", "tailwindcss-language-server",
        "emmet-language-server", "html-lsp", "css-lsp", "eslint-lsp",
        "json-lsp", "lua-language-server",
        "phpactor", -- só para o rename em PHP (Shift+F6)
        -- Formatters
        "pint", "blade-formatter", "prettierd", "stylua",
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "mason-org/mason.nvim", "saghen/blink.cmp" },
    config = function()
      -- Capabilities do blink.cmp para todos os servidores
      vim.lsp.config("*", {
        capabilities = require("blink.cmp").get_lsp_capabilities(),
      })

      -- PHP / Laravel
      vim.lsp.config("intelephense", {
        filetypes = { "php", "blade" },
        init_options = {
          -- Licença opcional (desbloqueia rename, implementations etc.)
          -- licenceKey = "SUA_CHAVE",
          globalStoragePath = vim.fn.stdpath("cache") .. "/intelephense",
        },
        settings = {
          intelephense = {
            files = {
              maxSize = 5000000,
              exclude = { "**/node_modules/**", "**/.git/**", "**/storage/framework/**" },
            },
            environment = { phpVersion = "8.4" },
          },
        },
        -- analisa o código com a versão de PHP do projeto (a do Herd), quando houver
        before_init = function(_, config)
          local v = require("config.project_php").version(config.root_dir)
          if v then config.settings.intelephense.environment.phpVersion = v .. ".0" end
        end,
      })

      -- Vue 3: o vtsls carrega o plugin do Vue e o vue_ls cuida do template
      local vue_ls_path = vim.fn.stdpath("data")
        .. "/mason/packages/vue-language-server/node_modules/@vue/language-server"

      vim.lsp.config("vtsls", {
        filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "vue" },
        settings = {
          typescript = {
            inlayHints = { parameterNames = { enabled = "literals" } },
          },
          vtsls = {
            tsserver = {
              globalPlugins = {
                {
                  name = "@vue/typescript-plugin",
                  location = vue_ls_path,
                  languages = { "vue" },
                  configNamespace = "typescript",
                },
              },
            },
          },
        },
      })

      vim.lsp.config("tailwindcss", {
        filetypes = { "html", "blade", "php", "vue", "javascript", "typescript", "css" },
      })

      vim.lsp.config("emmet_language_server", {
        filetypes = { "html", "blade", "vue", "css", "scss" },
      })

      vim.lsp.config("html", { filetypes = { "html", "blade" } })

      -- Phpactor: o rename (Shift+F6) de métodos, variáveis, propriedades e classes, que no
      -- Intelephense é pago, e as refatorações do Refactor This (Ctrl+T, config/refactor.lua),
      -- chamadas como comandos dele. Todo o resto (sugestões, erros, ir para definição)
      -- continua com o Intelephense, sem nada duplicado.
      vim.lsp.config("phpactor", {
        filetypes = { "php" },
        init_options = {
          ["language_server.diagnostics_on_open"] = false,
          ["language_server.diagnostics_on_save"] = false,
          ["language_server.diagnostics_on_update"] = false,
          ["language_server_phpstan.enabled"] = false,
          ["language_server_psalm.enabled"] = false,
          ["language_server_php_cs_fixer.enabled"] = false,
          ["indexer.exclude_patterns"] = { "/node_modules/**/*", "/storage/**/*", "/.git/**/*" },
          -- getters como no PhpStorm: getTotal() em vez de total()
          ["code_transform.refactor.generate_accessor.prefix"] = "get",
          ["code_transform.refactor.generate_accessor.upper_case_first"] = true,
        },
        handlers = {
          ["textDocument/publishDiagnostics"] = function() end,
          -- Projeto com .phpactor.json (o Tinkerwell cria um): o Phpactor pergunta se pode
          -- carregar o arquivo e a pergunta travava a abertura do PHP. Responde sozinho com a
          -- opção segura: não carrega e não pergunta de novo (para confiar: phpactor config:trust)
          ["window/showMessageRequest"] = function(err, params, ctx)
            if params and params.message and params.message:find("trust", 1, true) then
              for _, a in ipairs(params.actions or {}) do
                if a.title:find("don't ask me again", 1, true) then return a end
              end
            end
            return vim.lsp.handlers["window/showMessageRequest"](err, params, ctx)
          end,
        },
        on_init = function(client)
          local caps = client.server_capabilities
          for _, k in ipairs({
            "completionProvider", "hoverProvider", "signatureHelpProvider", "definitionProvider",
            "typeDefinitionProvider", "implementationProvider", "referencesProvider",
            "documentHighlightProvider", "documentSymbolProvider", "workspaceSymbolProvider",
            "codeActionProvider", "codeLensProvider", "documentFormattingProvider",
            "documentRangeFormattingProvider", "inlayHintProvider", "semanticTokensProvider",
            "selectionRangeProvider", "foldingRangeProvider",
            -- (executeCommandProvider fica: é por ele que o Refactor This chama as refatorações)
          }) do caps[k] = nil end
        end,
      })

      vim.lsp.config("lua_ls", {
        settings = { Lua = { diagnostics = { globals = { "vim" } } } },
      })

      vim.lsp.enable({
        "intelephense", "vtsls", "vue_ls", "tailwindcss", "emmet_language_server",
        "html", "cssls", "eslint", "jsonls", "lua_ls", "phpactor",
      })
    end,
  },
}
