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
    -- o padrão do plugin é o Telescope, que não está instalado (Cmd+N dava "Picker provider not found")
    opts = { features = { pickers = { provider = "fzf-lua" } } },
    config = function(_, opts)
      require("laravel").setup(opts)
      -- Make (Cmd+N): o plugin rodava "artisan make:x" sem o nome (o artisan falhava com
      -- "Not enough arguments") num terminal flutuante, e depois procurava o arquivo criado
      -- no texto desse terminal. Aqui: pede o nome, roda em segundo plano, abre o arquivo
      -- criado na janela de código e avisa o resultado numa notificação
      local app = require("laravel.core.app")
      local find_class = require("laravel.utils").find_class_from_make_output
      require("laravel.pickers.common.actions").make_run = function(command)
        vim.schedule(function()
          vim.ui.input({ prompt = "artisan " .. command.name }, function(input)
            if not input or vim.trim(input) == "" then return end
            local args = vim.fn.split(input, " ", false)
            table.insert(args, 1, command.name)
            vim.list_extend(args, { "--no-interaction", "--no-ansi" })
            local cmd = app("laravel.services.command_generator"):generate("artisan", args)
            local title = "artisan " .. command.name
            local cwd = vim.fn.getcwd()
            -- Fora de um terminal o artisan não diz o caminho do arquivo criado: um arquivo
            -- marcador antes de rodar permite achar depois o que ficou mais novo que ele
            local marker = vim.fn.tempname()
            vim.fn.writefile({}, marker)
            vim.system(cmd, { text = true, cwd = cwd }, function(res)
              vim.schedule(function()
                local created = {}
                if res.code == 0 then
                  local found = vim.system({ "find", ".", "(", "-path", "./vendor", "-o", "-path", "./node_modules",
                    "-o", "-path", "./storage", "-o", "-path", "./.git", ")", "-prune", "-o", "-type", "f",
                    "-newer", marker, "-print" }, { text = true, cwd = cwd }):wait()
                  for line in (found.stdout or ""):gmatch("[^\n]+") do table.insert(created, (line:gsub("^%./", ""))) end
                end
                os.remove(marker)
                local out = vim.trim((res.stdout or "") .. "\n" .. (res.stderr or ""))
                if res.code ~= 0 then
                  return vim.notify(out ~= "" and out or "O comando falhou", vim.log.levels.ERROR, { title = title })
                end
                -- abre o arquivo com o nome digitado (make:model X -m cria o model e a migration)
                local name = (args[2] or ""):gsub(".*[/\\]", "")
                local path = find_class(out .. "\n")
                if not (path and vim.fn.filereadable(path) == 1) then
                  path = nil
                  for _, f in ipairs(created) do
                    if vim.fn.fnamemodify(f, ":t:r") == name then path = f break end
                  end
                  path = path or created[1]
                end
                if not path then
                  return vim.notify(out ~= "" and out or "Nenhum arquivo criado", vim.log.levels.WARN, { title = title })
                end
                local main = require("config.panels").main_win()
                if main then vim.api.nvim_set_current_win(main) end
                vim.cmd.edit(vim.fn.fnameescape(path))
                vim.notify("Criado: " .. table.concat(#created > 0 and created or { path }, ", "), vim.log.levels.INFO, { title = title })
              end)
            end)
          end)
        end)
      end
      -- Popup de comando que terminou (deu erro, por ex.): q ou Esc fecha
      vim.api.nvim_create_autocmd("TermClose", {
        group = vim.api.nvim_create_augroup("laravel_popup_close", { clear = true }),
        callback = function(ev)
          vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(ev.buf) then return end
            local win = vim.fn.bufwinid(ev.buf)
            if win == -1 or vim.api.nvim_win_get_config(win).relative == "" then return end
            for _, key in ipairs({ "q", "<Esc>" }) do
              vim.keymap.set({ "n", "t" }, key, function() pcall(vim.api.nvim_win_close, win, true) end, { buffer = ev.buf, nowait = true })
            end
          end)
        end,
      })
    end,
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
