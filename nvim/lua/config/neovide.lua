-- Ajustes que só valem quando o Neovim roda dentro do Neovide
if not vim.g.neovide then return end

-- Monaspace Argon (github.com/githubnext/monaspace, brew install --cask font-monaspace).
-- Ela não tem os ícones da Nerd Font: a JetBrains Mono Nerd Font fica de reserva para eles.
vim.o.guifont = "Monaspace Argon,JetBrainsMono Nerd Font:h14"
-- um pouco mais de ar entre as linhas: o texto fica menos "apertado"
vim.opt.linespace = 6

-- Option esquerdo vira Alt (para Alt+Enter, Alt+F7...). O direito continua digitando acentos e símbolos
vim.g.neovide_input_macos_option_key_is_meta = "only_left"

vim.g.neovide_cursor_animation_length = 0.04
vim.g.neovide_cursor_trail_size = 0.3
vim.g.neovide_scroll_animation_length = 0.15
-- margens na cor do fundo escuro (Normal), emoldurando as ilhas
vim.g.neovide_padding_top = 10
vim.g.neovide_padding_right = 12
vim.g.neovide_padding_bottom = 4
vim.g.neovide_padding_left = 12
vim.g.neovide_scale_factor = 1.0

-- Janelas flutuantes com cantos arredondados (as ilhas do painel de Git, menus, popups)
vim.g.neovide_floating_corner_radius = 0.4
