return {
  "ibhagwan/fzf-lua",
  cmd = "FzfLua",
  opts = {
    files = {
      -- vendor e node_modules fora da busca de arquivos
      fd_opts = "--type f --hidden --exclude .git --exclude vendor --exclude node_modules",
    },
    global = {
      fd_opts = "--type f --hidden --exclude .git --exclude vendor --exclude node_modules",
    },
  },
  keys = {
    -- Search Everywhere: arquivos; comece com $ para abas abertas, @ para métodos do arquivo, # para classes do projeto
    { "<leader><space>", "<cmd>FzfLua global<cr>", desc = "Search Everywhere" },
    { "<leader>ff", "<cmd>FzfLua files<cr>", desc = "Buscar arquivo" },
    { "<leader>fg", "<cmd>FzfLua live_grep<cr>", desc = "Grep no projeto" },
    { "<leader>fw", "<cmd>FzfLua grep_cword<cr>", desc = "Grep da palavra" },
    { "<leader>fb", "<cmd>FzfLua buffers<cr>", desc = "Buffers abertos" },
    { "<leader>fr", "<cmd>FzfLua oldfiles<cr>", desc = "Arquivos recentes" },
    { "<leader>fd", "<cmd>FzfLua diagnostics_document<cr>", desc = "Diagnósticos" },
    { "<leader>gS", "<cmd>FzfLua git_status<cr>", desc = "Buscar nas alterações do git" },
  },
}
