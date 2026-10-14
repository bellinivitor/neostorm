local map = vim.keymap.set

map("n", "<Esc>", "<cmd>nohlsearch<cr>")
map("n", "<leader>w", "<cmd>w<cr>", { desc = "Salvar" })
map("n", "<leader>q", "<cmd>q<cr>", { desc = "Fechar janela" })

-- Navegação entre splits
map("n", "<C-h>", "<C-w>h")
map("n", "<C-j>", "<C-w>j")
map("n", "<C-k>", "<C-w>k")
map("n", "<C-l>", "<C-w>l")

-- Buffers
map("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Buffer anterior" })
map("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Próximo buffer" })

-- Mover linhas no visual
map("v", "J", ":m '>+1<cr>gv=gv")
map("v", "K", ":m '<-2<cr>gv=gv")

-- Diagnósticos
map("n", "<leader>d", vim.diagnostic.open_float, { desc = "Diagnóstico da linha" })
map("n", "[d", function() vim.diagnostic.jump({ count = -1, float = true }) end)
map("n", "]d", function() vim.diagnostic.jump({ count = 1, float = true }) end)
