local opt = vim.opt

opt.number = true
-- números relativos: a linha do cursor mostra o número real e as outras a distância até ela
-- (para pular com 5k / 5j); os painéis desligam isso nas próprias janelas
opt.relativenumber = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.termguicolors = true
opt.scrolloff = 8
opt.numberwidth = 5
opt.laststatus = 3
-- Sem traço entre as janelas: cada coluna fica como uma ilha, como no tema Islands do PhpStorm.
-- O separador é um bloco parcial na cor da ilha sobre o fundo (canvas), então só uma faixa
-- fina do fundo aparece: 3/8 da largura entre colunas (▋) e 1/8 da altura entre linhas (▇).
-- Cores em colors/phpstorm.lua (WinSeparator)
local V, H = "\u{258B}", "\u{2587}"
opt.fillchars = {
  eob = " ", fold = " ", diff = "\u{2571}",
  vert = V, vertleft = V, vertright = V, verthoriz = V,
  horiz = H, horizup = H, horizdown = H,
}
opt.pumheight = 12
opt.wrap = false

-- PSR-12 usa 4 espaços; Vue/JS ficam com 2 via autocmd
opt.expandtab = true
opt.shiftwidth = 4
opt.tabstop = 4
opt.smartindent = true

opt.ignorecase = true
opt.smartcase = true
opt.splitright = true
opt.splitbelow = true
opt.clipboard = "unnamedplus"
opt.undofile = true
opt.swapfile = false
opt.updatetime = 250
opt.timeoutlen = 400
opt.completeopt = { "menu", "menuone", "noselect" }
opt.mouse = "a"

-- Garante que *.blade.php vire filetype blade (e não php)
vim.filetype.add({
  pattern = {
    [".*%.blade%.php"] = "blade",
  },
})

-- Erros como no PhpStorm: sublinhado ondulado no código; a mensagem aparece só
-- na linha do cursor (e completa com espaço d). Sem letras E/W ao lado do número.
vim.diagnostic.config({
  underline = true,
  virtual_text = { current_line = true, spacing = 4, prefix = "\u{25CF}" },
  signs = false,
  severity_sort = true,
  update_in_insert = false,
  float = { border = "rounded", source = true, header = "" },
})

-- Diff mais parecido com o do PhpStorm: alinha linhas alteradas e não esconde trechos
vim.opt.diffopt = { "internal", "filler", "closeoff", "algorithm:histogram", "indent-heuristic", "linematch:60", "context:99999" }
