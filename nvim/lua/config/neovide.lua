-- Ajustes que só valem quando o Neovim roda dentro do Neovide
if not vim.g.neovide then return end

vim.o.guifont = "JetBrainsMono Nerd Font:h14"
vim.opt.linespace = 4

-- Option esquerdo vira Alt (para Alt+Enter, Alt+F7...). O direito continua digitando acentos e símbolos
vim.g.neovide_input_macos_option_key_is_meta = "only_left"

vim.g.neovide_cursor_animation_length = 0.04
vim.g.neovide_cursor_trail_size = 0.3
vim.g.neovide_scroll_animation_length = 0.15
-- margens na cor do fundo escuro (Normal), emoldurando as ilhas
vim.g.neovide_padding_top = 6
vim.g.neovide_padding_right = 6
vim.g.neovide_padding_bottom = 0
vim.g.neovide_padding_left = 6
vim.g.neovide_scale_factor = 1.0

-- Janelas flutuantes com cantos arredondados (as ilhas do painel de Git, menus, popups)
vim.g.neovide_floating_corner_radius = 0.4
