-- Claude Code integrado ao Neovim (como a extensão do VS Code/JetBrains):
-- o Claude vê o arquivo e a seleção atuais, e as alterações que ele propõe
-- abrem como diff no Neovim para aceitar ou recusar.
-- Ele abre no painel próprio, à direita (config/claude_panel.lua), com o resumo de consumo.
return {
  "coder/claudecode.nvim",
  dependencies = { "folke/snacks.nvim" },
  event = "VeryLazy",
  opts = function()
    return {
      auto_start = true,       -- servidor da integração sobe junto com o Neovim
      track_selection = true,  -- o Claude acompanha o arquivo/seleção atuais
      -- com a status line que grava o consumo (contexto, sessão, semana) para o painel
      terminal_cmd = require("config.claude_panel").cmd,
      terminal = {
        provider = require("config.claude_panel").provider,
      },
      diff_opts = {
        layout = "vertical",
        open_in_new_tab = false,
      },
    }
  end,
  keys = {
    -- Abrir/focar o Claude Code (Cmd+Esc, como na extensão do VS Code)
    { "<D-Esc>", "<cmd>ClaudeCodeFocus<cr>", mode = { "n", "i", "v", "t" }, desc = "Claude Code" },
    { "<leader>ac", "<cmd>ClaudeCode<cr>", desc = "Claude Code: abrir/fechar" },
    { "<leader>af", "<cmd>ClaudeCodeFocus<cr>", desc = "Claude Code: focar" },
    { "<leader>ar", "<cmd>ClaudeCode --resume<cr>", desc = "Claude Code: retomar conversa" },
    { "<leader>aC", "<cmd>ClaudeCode --continue<cr>", desc = "Claude Code: continuar última" },
    { "<leader>am", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Claude Code: escolher modelo" },
    -- Mandar contexto para o Claude
    { "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Claude Code: enviar seleção" },
    { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "Claude Code: adicionar arquivo atual" },
    -- Diffs propostos pelo Claude
    { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Claude Code: aceitar diff" },
    { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Claude Code: recusar diff" },
  },
}
