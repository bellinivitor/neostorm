-- Leader precisa ser definido antes do lazy.nvim
vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("config.options")
require("config.neovide")
require("config.keymaps")
require("config.phpstorm")
require("config.tabs").setup()
require("config.tests")
require("config.recent_locations")
require("config.usages")
require("config.endpoints") -- destino das rotas no fim das linhas de routes/*.php
require("config.laravel_links") -- Policy e route('nome'): Cmd+clique e URL no fim da linha
require("config.autocmds")
require("config.conflicts") -- blocos em conflito coloridos e janela de conflitos (<leader>gx)
require("config.lazy")
