-- Atalhos no estilo PhpStorm (keymap macOS).
-- As teclas com Cmd (<D-...>) funcionam no Ghostty (com ~/.config/ghostty/config) e no Neovide.
-- Em outros terminais use os atalhos com espaço.
local map = vim.keymap.set

-- Cmd+Shift+X chega como <D-S-x> ou <D-X> dependendo da versão; mapeia os dois
local function cmd_shift(key, rhs, desc, mode)
  map(mode or "n", "<D-S-" .. key .. ">", rhs, { desc = desc })
  if key:upper() ~= key then
    map(mode or "n", "<D-" .. key:upper() .. ">", rhs, { desc = desc })
  end
end

-- Edição básica de Mac
map({ "n", "i", "v" }, "<D-s>", "<cmd>w<cr><esc>", { desc = "Salvar" })
map("n", "<D-z>", "u", { desc = "Desfazer" })
map("i", "<D-z>", "<C-o>u", { desc = "Desfazer" })
cmd_shift("z", "<C-r>", "Refazer")
map("n", "<D-a>", "ggVG", { desc = "Selecionar tudo" })
map("v", "<D-c>", '"+y', { desc = "Copiar" })
map("v", "<D-x>", '"+d', { desc = "Recortar" })
-- Sem seleção, como no PhpStorm: copia/recorta a linha inteira
map("n", "<D-c>", '"+yy', { desc = "Copiar linha" })
map("n", "<D-x>", '"+dd', { desc = "Recortar linha" })
map("n", "<D-v>", '"+P', { desc = "Colar" })
map("v", "<D-v>", '"+P', { desc = "Colar" })
map({ "i", "c" }, "<D-v>", "<C-r>+", { desc = "Colar" })
map("t", "<D-v>", [[<C-\><C-n>"+Pi]], { desc = "Colar" })

-- Linhas
map("n", "<D-/>", "gcc", { remap = true, desc = "Comentar linha" })
map("v", "<D-/>", "gc", { remap = true, desc = "Comentar seleção" })
map("i", "<D-/>", "<esc>gcca", { remap = true, desc = "Comentar linha" })
map("n", "<D-d>", "<cmd>t.<cr>", { desc = "Duplicar linha" })
map("v", "<D-d>", "y`>p", { desc = "Duplicar seleção" })
map("n", "<D-BS>", "dd", { desc = "Apagar linha" })
map("i", "<D-BS>", "<C-o>dd", { desc = "Apagar linha" })
for _, mod in ipairs({ "D-S", "M-S" }) do
  map("n", "<" .. mod .. "-Up>", "<cmd>m .-2<cr>==", { desc = "Mover linha para cima" })
  map("n", "<" .. mod .. "-Down>", "<cmd>m .+1<cr>==", { desc = "Mover linha para baixo" })
  map("v", "<" .. mod .. "-Up>", ":m '<-2<cr>gv=gv", { desc = "Mover seleção para cima" })
  map("v", "<" .. mod .. "-Down>", ":m '>+1<cr>gv=gv", { desc = "Mover seleção para baixo" })
end

-- Option+seta pula palavra, Option+Backspace apaga palavra (como no macOS)
-- No Ghostty chegam como Alt+f / Alt+b (o mesmo que o shell usa); no Neovide como Alt+seta
for _, lhs in ipairs({ "<M-f>", "<M-Right>" }) do
  map({ "n", "v" }, lhs, "e", { desc = "Fim da palavra" })
  map("i", lhs, "<C-o>e<Right>", { desc = "Fim da palavra" })
  map("c", lhs, "<S-Right>", { desc = "Próxima palavra" })
end
for _, lhs in ipairs({ "<M-b>", "<M-Left>" }) do
  map({ "n", "v" }, lhs, "b", { desc = "Início da palavra" })
  map("i", lhs, "<C-o>b", { desc = "Início da palavra" })
  map("c", lhs, "<S-Left>", { desc = "Palavra anterior" })
end
map({ "i", "c" }, "<M-BS>", "<C-w>", { desc = "Apagar palavra" })

-- Busca e navegação
map("n", "<D-f>", "/", { desc = "Buscar no arquivo" })
map("n", "<D-r>", ":%s/", { desc = "Substituir no arquivo" })
cmd_shift("f", "<cmd>FzfLua live_grep<cr>", "Find in Files")
cmd_shift("o", "<cmd>FzfLua files<cr>", "Go to File")
map("n", "<D-o>", "<cmd>FzfLua lsp_live_workspace_symbols<cr>", { desc = "Go to Class/Symbol" })
map("n", "<D-e>", "<cmd>FzfLua oldfiles cwd_only=true<cr>", { desc = "Arquivos recentes" })
cmd_shift("e", function() require("config.recent_locations").open() end, "Recent Locations")
cmd_shift("a", "<cmd>FzfLua keymaps<cr>", "Find Action")
map("n", "<D-l>", ":", { desc = "Ir para linha (digite o número)" })
map("n", "<D-[>", "<C-o>", { desc = "Voltar" })
map("n", "<D-]>", "<C-i>", { desc = "Avançar" })
cmd_shift("[", function() require("config.tabs").cycle(-1) end, "Aba anterior")
cmd_shift("]", function() require("config.tabs").cycle(1) end, "Próxima aba")
map("n", "<D-{>", function() require("config.tabs").cycle(-1) end, { desc = "Aba anterior" })
map("n", "<D-}>", function() require("config.tabs").cycle(1) end, { desc = "Próxima aba" })

-- Código (LSP)
-- Cmd+B e Cmd+clique: num uso vai para a declaração; na declaração mostra os usos
map("n", "<D-b>", function() require("config.smart_click").go() end, { desc = "Go to Declaration or Usages" })
-- Cmd+clique (Neovide) e Option+clique (Ghostty: o terminal não repassa o Cmd no clique)
-- Apertar só posiciona o cursor; a ação roda ao SOLTAR o botão. Se rodasse ao apertar, a lista
-- de usos abria com o botão ainda pressionado e o "soltar" caía dentro dela, tirando o foco.
for _, mod in ipairs({ "D", "M" }) do
  map({ "n", "i", "t" }, "<" .. mod .. "-LeftMouse>", function() require("config.smart_click").press() end, { desc = "Go to Declaration or Usages" })
  map({ "n", "i", "v", "t" }, "<" .. mod .. "-LeftRelease>", function() require("config.smart_click").release() end)
  map({ "n", "i", "v", "t" }, "<" .. mod .. "-LeftDrag>", "<Nop>")
end
map("n", "<D-M-b>", "<cmd>FzfLua lsp_implementations<cr>", { desc = "Go to Implementation" })
local find_usages = function() require("config.smart_click").find_usages() end
map("n", "<M-F7>", find_usages, { desc = "Find Usages" })
-- No terminal, Shift+F e Alt+F chegam como F13 em diante: Shift+F2 = F14, Shift+F6 = F18, Alt+F7 = F55
map("n", "<F55>", find_usages, { desc = "Find Usages" })
map("n", "<F18>", vim.lsp.buf.rename, { desc = "Rename" })
map("n", "<F14>", function() vim.diagnostic.jump({ count = -1, float = true }) end, { desc = "Erro anterior" })
map("n", "<D-F12>", "<cmd>FzfLua lsp_document_symbols<cr>", { desc = "File Structure" })
map({ "n", "v" }, "<M-CR>", vim.lsp.buf.code_action, { desc = "Show Intention Actions" })
map("n", "<S-F6>", vim.lsp.buf.rename, { desc = "Rename" })
-- Ctrl+T (Refactor This no PhpStorm do Mac): vai direto para o Rename, sem tecla F
-- Refactor This (Ctrl+T, como no PhpStorm do Mac): Rename, Extract Method, Introduce Variable,
-- getters/setters… (config/refactor.lua). Com seleção, oferece as extrações.
map("n", "<C-t>", function() require("config.refactor").open() end, { desc = "Refactor This" })
map("x", "<C-t>", function() require("config.refactor").open_visual() end, { desc = "Refactor This" })
map("n", "<F1>", vim.lsp.buf.hover, { desc = "Quick Documentation" })
map({ "n", "i" }, "<D-p>", vim.lsp.buf.signature_help, { desc = "Parameter Info" })
map("n", "<F2>", function() vim.diagnostic.jump({ count = 1, float = true }) end, { desc = "Próximo erro" })
map("n", "<S-F2>", function() vim.diagnostic.jump({ count = -1, float = true }) end, { desc = "Erro anterior" })
map({ "n", "v" }, "<D-M-l>", function() _G.ReformatCode() end, { desc = "Reformat Code" })
-- Optimize Imports (Ctrl+Option+O no PhpStorm)
map("n", "<C-M-o>", function() require("config.imports").optimize() end, { desc = "Optimize Imports" })
map("n", "<leader>co", function() require("config.imports").optimize() end, { desc = "Optimize Imports" })

-- Botão direito: no painel da direita abre Ver diff / Rollback; no resto, o menu padrão
map("n", "<RightMouse>", function() require("config.git_rollback").right_click() end, { desc = "Menu de contexto" })
map("n", "<RightRelease>", "<Nop>")

-- Laravel (Cmd+N = Generate)
map("n", "<D-n>", function() Laravel.pickers.make() end, { desc = "Laravel make" })

-- Zoom da fonte no Neovide
map("n", "<D-=>", function() vim.g.neovide_scale_factor = (vim.g.neovide_scale_factor or 1) * 1.1 end, { desc = "Aumentar fonte" })
map("n", "<D-->", function() vim.g.neovide_scale_factor = (vim.g.neovide_scale_factor or 1) / 1.1 end, { desc = "Diminuir fonte" })
map("n", "<D-M-0>", function() vim.g.neovide_scale_factor = 1 end, { desc = "Fonte padrão" })

-- Run Anything: Cmd+Shift+X (de qualquer modo, inclusive dentro do terminal)
local function run_anything() require("config.run_anything").open() end
cmd_shift("x", run_anything, "Run Anything", { "n", "i", "v", "t" })
map("n", "<leader>R", run_anything, { desc = "Run Anything" })

-- Testes (Pest): ▶ na margem e painel Run (config/tests.lua)
local function tests(fn) return function() require("config.tests")[fn]() end end
map("n", "<leader>tn", tests("nearest"), { desc = "Teste sob o cursor" })
map("n", "<leader>tf", tests("file"), { desc = "Testes do arquivo" })
map("n", "<leader>ts", tests("suite"), { desc = "Suíte inteira" })
map("n", "<leader>tl", tests("again"), { desc = "Repetir o último teste" })
map("n", "<leader>tc", tests("with_coverage"), { desc = "Rodar com cobertura" })
map("n", "<leader>tC", tests("coverage_clear"), { desc = "Esconder a cobertura" })

-- Conflitos de merge/rebase: lista dos arquivos, continuar e abortar (config/conflicts.lua)
map("n", "<leader>gx", function() require("config.conflicts").open() end, { desc = "Conflitos" })

-- Problems: erros e avisos agrupados por arquivo (Cmd+6, como no PhpStorm)
map("n", "<D-6>", function() require("config.problems").toggle() end, { desc = "Problems" })
map("n", "<leader>xx", function() require("config.problems").toggle() end, { desc = "Problems" })

-- Exemplo de consumo da rota (URL completa do .env + payload): na linha de routes/*.php ou no
-- método do controller (config/route_example.lua)
local function route_example() require("config.route_example").at_cursor() end
map("n", "<D-M-e>", route_example, { desc = "Exemplo de requisição da rota" })
map("n", "<leader>le", route_example, { desc = "Exemplo de requisição da rota" })

-- Tinker na seleção (ou na linha atual): resultado num popup (config/tinker.lua)
local function tinker() require("config.tinker").at_cursor() end
map({ "n", "v" }, "<D-M-t>", tinker, { desc = "Tinker na seleção" })
map({ "n", "v" }, "<leader>lt", tinker, { desc = "Tinker na seleção" })

-- Contas do Git: credencial (Chaves do macOS) e identidade de commit por servidor (config/git_accounts.lua)
map("n", "<leader>gA", function() require("config.git_accounts").open() end, { desc = "Contas do Git" })
vim.api.nvim_create_user_command("GitAccounts", function() require("config.git_accounts").open() end, { desc = "Contas do Git" })
