return {
  -- O tema "phpstorm" fica em colors/phpstorm.lua (cores tiradas do PhpStorm).
  -- Tokyonight fica de reserva: :colorscheme tokyonight-night
  { "folke/tokyonight.nvim", lazy = true },
  { "nvim-tree/nvim-web-devicons", lazy = true },

  -- Snacks: notificações, terminal, lazygit, guias de indentação,
  -- destaque de usos da palavra sob o cursor e seletor de projetos
  {
    "folke/snacks.nvim",
    lazy = false,
    priority = 900,
    opts = function() return {
      bigfile = { enabled = true },
      notifier = { enabled = true },
      indent = { enabled = true },
      -- Caixinhas de texto (nome da nova branch etc.) com o mesmo visual das listas de escolha
      input = { enabled = true, icon = "\u{276F}", icon_hl = "SnacksInputIcon", icon_pos = "left", prompt_pos = "title" },
      styles = {
        input = { width = 72, row = 0.32, relative = "editor", border = "rounded", title_pos = "center" },
      },
      words = { enabled = true },
      picker = { enabled = true },
      lazygit = { enabled = true },
      dashboard = require("config.dashboard").config(),
    } end,
    keys = {
      -- Painel de terminal com abas (config/terminal.lua)
      { "<M-F12>", function() require("config.terminal").toggle() end, mode = { "n", "t" }, desc = "Terminal" },
      { "<F60>", function() require("config.terminal").toggle() end, mode = { "n", "t" }, desc = "Terminal" }, -- Alt+F12 no Ghostty
      { "<C-\\>", function() require("config.terminal").toggle() end, mode = { "n", "t" }, desc = "Terminal" },
      -- Ctrl+/ (alguns terminais enviam como Ctrl+_), funciona no teclado ABNT
      { "<C-/>", function() require("config.terminal").toggle() end, mode = { "n", "t" }, desc = "Terminal" },
      { "<C-_>", function() require("config.terminal").toggle() end, mode = { "n", "t" }, desc = "Terminal" },
      { "<leader>tt", function() require("config.terminal").toggle() end, desc = "Terminal" },
      -- Abas do terminal: Cmd+T nova, Cmd+W fecha (dentro do terminal), Cmd+Shift+[ ] troca
      { "<D-t>", function() require("config.terminal").new() end, mode = { "n", "t" }, desc = "Nova aba de terminal" },
      { "<leader>tN", function() require("config.terminal").new() end, desc = "Nova aba de terminal" },
      { "<D-w>", function() require("config.terminal").close() end, mode = "t", desc = "Fechar aba do terminal" },
      { "<D-S-]>", function() require("config.terminal").next(1) end, mode = "t", desc = "Próxima aba do terminal" },
      { "<D-S-[>", function() require("config.terminal").next(-1) end, mode = "t", desc = "Aba anterior do terminal" },
      { "<D-}>", function() require("config.terminal").next(1) end, mode = "t", desc = "Próxima aba do terminal" },
      { "<D-{>", function() require("config.terminal").next(-1) end, mode = "t", desc = "Aba anterior do terminal" },
      -- Posição do painel
      { "<M-t>", function() require("config.terminal").cycle() end, mode = { "n", "t" }, desc = "Terminal: mudar posição" },
      { "<leader>tm", function() require("config.terminal").cycle() end, desc = "Terminal: mudar posição" },
      { "<leader>tb", function() require("config.terminal").set("bottom") end, desc = "Terminal embaixo" },
      { "<leader>tr", function() require("config.terminal").set("right") end, desc = "Terminal à direita" },
      { "<leader>tg", function() require("config.terminal").set("float") end, desc = "Terminal flutuante" },
      -- Janela de Git no estilo do PhpStorm (config/git_log.lua); Cmd+9 como no PhpStorm
      { "<leader>gg", function() require("config.git_log").toggle() end, desc = "Git (log)" },
      { "<D-9>", function() require("config.git_log").toggle() end, desc = "Git (log)" },
      { "<leader>fp", function() Snacks.picker.projects() end, desc = "Projetos recentes" },
      { "<leader>bd", function() Snacks.bufdelete() end, desc = "Fechar aba" },
      { "<D-w>", function() Snacks.bufdelete() end, desc = "Fechar aba" },
    },
  },

  -- Árvore do projeto (painel Project do PhpStorm)
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    cmd = "Neotree",
    dependencies = { "nvim-lua/plenary.nvim", "MunifTanjim/nui.nvim", "nvim-tree/nvim-web-devicons" },
    keys = {
      { "<leader>e", function() require("config.activity_bar").items[1].toggle() end, desc = "Projeto" },
      { "<D-1>", function() require("config.activity_bar").items[1].toggle() end, desc = "Projeto" },
      -- Janela de Commit (como Cmd+0 / Cmd+K no PhpStorm)
      { "<leader>gs", function() require("config.commit").toggle() end, desc = "Commit" },
      -- Branches (o mesmo popup do clique na branch, na barra de baixo)
      { "<leader>gB", function() require("config.branches").open() end, desc = "Branches" },
      { "<D-M-n>", function() require("config.branches").new_branch() end, desc = "Nova branch" },
      { "<D-0>", function() require("config.commit").toggle() end, desc = "Commit" },
      { "<D-k>", function() require("config.commit").open({ focus_message = true }) end, desc = "Commit" },
      { "<D-S-k>", function() require("config.commit").push() end, desc = "Push" },
      { "<D-K>", function() require("config.commit").push() end, desc = "Push" },
    },
    opts = {
      close_if_last_window = true,
      open_files_do_not_replace_types = { "terminal", "qf", "commit_list", "gitcommit", "commit_actions", "activity_bar", "aerial", "popup_menu" },
      sources = { "filesystem", "git_status" },
      -- (as abas horizontais saíram: a barra vertical da direita faz esse papel)
      source_selector = { winbar = false },
      window = {
        position = "right",
        width = 38,
        mappings = {
          -- (o botão direito com o menu Ver diff / Rollback fica em config/phpstorm.lua)
          -- D mostra o diff com o último commit; Cmd+Alt+Z faz o Rollback
          ["D"] = function(state) require("config.git_rollback").tree_diff(state) end,
          ["<D-M-z>"] = function(state) require("config.git_rollback").tree_rollback(state) end,
        },
      },
      git_status = {
        window = {
          mappings = {
            ["A"] = "git_add_all",
            ["ga"] = "git_add_file",
            ["gu"] = "git_unstage_file",
            -- Rollback: arquivo alterado volta ao último commit; arquivo novo é apagado (pede confirmação)
            ["gr"] = function(state) require("config.git_rollback").tree_rollback(state) end,
            ["gc"] = "git_commit",
            ["gp"] = "git_push",
          },
        },
      },
      filesystem = {
        follow_current_file = { enabled = true },
        use_libuv_file_watcher = true,
        filtered_items = {
          visible = true,
          hide_dotfiles = false,
          hide_gitignored = false,
          never_show = { ".DS_Store", ".git" },
        },
      },
    },
  },

  -- (as abas de arquivos ficam em config/tabs.lua: cards arredondados, sem plugin)

  -- Breadcrumbs clicáveis (Classe > método) no topo do editor
  {
    "Bekaboo/dropbar.nvim",
    lazy = false,
    opts = {
      bar = {
        -- Só em arquivos de código (no painel de terminal fica a barra de abas)
        enable = function(buf, win)
          if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then return false end
          return vim.bo[buf].buftype == ""
            and vim.api.nvim_buf_get_name(buf) ~= ""
            and vim.api.nvim_win_get_config(win).relative == ""
            and not vim.wo[win].diff
        end,
      },
    },
  },

  -- Painel Structure (lista de métodos e propriedades do arquivo)
  {
    "stevearc/aerial.nvim",
    cmd = { "AerialToggle", "AerialOpen" },
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    -- Structure abre à direita, no mesmo lugar do Projeto e do Commit (um de cada vez).
    -- placement "edge": encosta na borda, e não ao lado da janela que estiver com o foco
    opts = { layout = { default_direction = "right", placement = "edge", min_width = 30, max_width = 46 }, attach_mode = "global" },
    keys = {
      { "<D-7>", function() require("config.activity_bar").items[3].toggle() end, desc = "Structure" },
      { "<leader>cs", function() require("config.activity_bar").items[3].toggle() end, desc = "Structure" },
    },
  },

  -- Find and Replace no projeto inteiro (Cmd+Shift+R)
  {
    "MagicDuck/grug-far.nvim",
    cmd = "GrugFar",
    opts = {},
    keys = {
      { "<D-S-r>", "<cmd>GrugFar<cr>", desc = "Substituir no projeto" },
      { "<D-R>", "<cmd>GrugFar<cr>", desc = "Substituir no projeto" },
      { "<leader>fR", "<cmd>GrugFar<cr>", desc = "Substituir no projeto" },
    },
  },

  -- Reabre os arquivos do projeto onde você parou
  {
    "folke/persistence.nvim",
    lazy = false,
    config = function()
      -- A sessão não guarda painéis (árvore, terminal, structure), só os arquivos.
      -- Guardar o painel da árvore causava o erro E95 "Buffer with this name already exists".
      vim.opt.sessionoptions = { "buffers", "curdir", "tabpages", "winsize", "help", "globals", "skiprtp", "folds" }

      local function close_panels()
        pcall(vim.cmd, "Neotree close")
        pcall(vim.cmd, "AerialCloseAll")
        pcall(function() require("config.commit").close() end)
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          local name = vim.api.nvim_buf_get_name(buf)
          local ft = vim.bo[buf].filetype
          if ft == "neo-tree" or name:match("neo%-tree ") or vim.bo[buf].buftype == "terminal" then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
          end
        end
      end

      local group = vim.api.nvim_create_augroup("vitor_session", { clear = true })
      vim.api.nvim_create_autocmd("User", { group = group, pattern = "PersistenceSavePre", callback = close_panels })
      -- Limpa sessões antigas que ainda tenham o painel salvo
      vim.api.nvim_create_autocmd("User", { group = group, pattern = "PersistenceLoadPost", callback = close_panels })

      local persistence = require("persistence")
      persistence.setup()
      vim.api.nvim_create_autocmd("VimEnter", {
        nested = true,
        callback = function()
          if vim.fn.argc() == 0 and not vim.g.started_with_stdin then
            persistence.load()
            vim.schedule(function() vim.cmd("Neotree show") end)
          end
        end,
      })
    end,
  },

  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    -- Barra de baixo como a do PhpStorm: modo à esquerda, infos e branch à direita
    opts = function()
      local c = require("config.palette")
      local bar = { fg = c.fg_dim, bg = c.bg_alt }
      local function mode(bg) return { a = { fg = "#FFFFFF", bg = bg, gui = "bold" }, b = bar, c = bar } end
      local theme = {
        normal = mode("#2E436E"),
        insert = mode("#3D6B44"),
        visual = mode("#6B4C8A"),
        replace = mode("#8A3A3A"),
        command = mode("#6B5A2E"),
        terminal = mode("#2E5E6B"),
        inactive = { a = bar, b = bar, c = bar },
      }
      return {
        options = {
          globalstatus = true,
          theme = theme,
          component_separators = "",
          section_separators = "",
          disabled_filetypes = { statusline = {} },
        },
        sections = {
          lualine_a = { { "mode", fmt = function(s) return s:sub(1, 1) end } },
          lualine_b = {},
          -- (o caminho do arquivo fica só no topo, no breadcrumb clicável do dropbar)
          lualine_c = {},
          lualine_x = {
            { "diagnostics", symbols = { error = "\u{F0159} ", warn = "\u{F0026} ", info = "\u{F02FC} ", hint = "\u{F0335} " } },
            { function() return "PHP" end, cond = function() return vim.bo.filetype == "php" end },
            "encoding",
          },
          lualine_y = { { "location", padding = { left = 1, right = 1 } } },
          lualine_z = { {
            "branch", icon = "\u{F062C}", color = { fg = c.fg, bg = c.bg_alt },
            -- clicar na branch abre o popup de branches (como no PhpStorm)
            on_click = function() require("config.branches").open() end,
          } },
        },
      }
    end,
  },
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      spec = {
        { "<leader>b", group = "abas" },
        { "<leader>c", group = "código" },
        { "<leader>f", group = "buscar" },
        { "<leader>g", group = "git" },
        { "<leader>l", group = "laravel" },
        { "<leader>s", group = "símbolos" },
        { "<leader>t", group = "testes / terminal" },
        { "<leader>a", group = "claude code" },
      },
    },
  },
  {
    "lewis6991/gitsigns.nvim",
    event = "BufReadPre",
    opts = {
      current_line_blame = false,
      -- Barras finas como no PhpStorm; triângulo onde linhas foram apagadas
      signs = {
        add = { text = "▎" },
        change = { text = "▎" },
        delete = { text = "\u{25B8}" }, -- ▸
        topdelete = { text = "\u{25B8}" },
        changedelete = { text = "▎" },
        untracked = { text = "▎" },
      },
      signs_staged_enable = false,
      preview_config = { border = "rounded", style = "minimal", relative = "cursor", row = 1, col = 1 },
    },
    config = function(_, opts)
      require("gitsigns").setup(opts)
      -- Coluna: diagnóstico, número da linha e a barra do git (clicável)
      vim.o.statuscolumn = "%!v:lua.require'config.gitgutter'.statuscolumn()"
    end,
    keys = {
      -- Blame só quando quiser (liga e desliga)
      { "<leader>gb", "<cmd>Gitsigns toggle_current_line_blame<cr>", desc = "Blame na linha (liga/desliga)" },
      -- Menu da alteração (o mesmo do clique na barra)
      { "<leader>gh", function() require("config.gitgutter").menu() end, desc = "Alteração: diff / rollback" },
      { "<leader>gd", function() require("gitsigns").preview_hunk() end, desc = "Ver diff da alteração" },
      { "<leader>gr", function() require("gitsigns").reset_hunk() end, desc = "Rollback da alteração" },
      { "<D-M-z>", function() require("gitsigns").reset_hunk() end, desc = "Rollback Lines" },
      { "<leader>gr", function() require("gitsigns").reset_hunk({ vim.fn.line("v"), vim.fn.line(".") }) end, mode = "v", desc = "Rollback das linhas selecionadas" },
      { "<D-M-z>", function() require("gitsigns").reset_hunk({ vim.fn.line("v"), vim.fn.line(".") }) end, mode = "v", desc = "Rollback Lines" },
      -- Próxima / anterior alteração
      { "]h", function() require("gitsigns").nav_hunk("next") end, desc = "Próxima alteração" },
      { "[h", function() require("gitsigns").nav_hunk("prev") end, desc = "Alteração anterior" },
    },
  },
  { "windwp/nvim-autopairs", event = "InsertEnter", opts = {} },
  {
    "stevearc/oil.nvim",
    lazy = false,
    opts = { view_options = { show_hidden = true } },
    keys = { { "-", "<cmd>Oil<cr>", desc = "Explorador (pasta atual)" } },
  },
}
