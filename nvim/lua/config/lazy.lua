local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = { { import = "plugins" } },
  install = { colorscheme = { "phpstorm" } },
  checker = { enabled = true, notify = false },
  change_detection = { notify = false },
})

-- Tema com as cores do PhpStorm (colors/phpstorm.lua)
vim.cmd.colorscheme("phpstorm")

-- Barra vertical de ferramentas na borda direita (config/activity_bar.lua)
require("config.activity_bar").setup()

-- Painéis presos ao próprio conteúdo e dashboard quando não há arquivo aberto
require("config.panels")
require("config.dashboard").setup()
