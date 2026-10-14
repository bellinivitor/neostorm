-- Painel Terminal: abas de shell (o painel em si fica em config/term_panel.lua)
--   Terminal  ( Local × ) ( Local (2) × ) ( + )
-- (o Claude Code tem painel próprio, à direita: config/claude_panel.lua)
-- Cada aba é um terminal; × fecha (encerra o processo), + abre outra.
local M = require("config.term_panel")({
  id = "terminal",
  title = "Terminal",
  module = "config.terminal",
  other = "config.run_panel",
  new_button = true,
  tab_icon = function() return "\u{F489}", "TabCard" end, -- 
})


-- Cores dos painéis Terminal e Run (seguem o tema)
local function colors()
  local ok, c = pcall(require, "config.palette")
  if not ok then return end
  local set = vim.api.nvim_set_hl
  set(0, "TermPanel", { fg = c.fg, bg = c.bg })
  set(0, "TermTabBar", { fg = c.fg_dim, bg = c.bg })
  set(0, "TermTabTitle", { fg = c.fg, bg = c.bg, bold = true })
  local card = vim.api.nvim_get_hl(0, { name = "TabCard" }).bg
  local sel = vim.api.nvim_get_hl(0, { name = "TabCardSel" }).bg
  -- ícones das abas com o fundo de cada tipo de card:
  -- ✳ laranja do Claude Code; no Run ▶ azul rodando, ✓ verde ok, ✗ vermelho falhou, ■ cinza parado
  for name, fg in pairs({ TermTabClaude = "#D97757", TermTabRun = c.accent, TermTabOk = c.hint, TermTabFail = c.error, TermTabStopped = c.fg_faint }) do
    set(0, name, { fg = fg, bg = card })
    set(0, name .. "Sel", { fg = fg, bg = sel })
  end
  -- botões Rerun e Stop do painel Run
  set(0, "TermToolRerun", { fg = c.hint, bg = card })
  set(0, "TermToolStop", { fg = c.error, bg = card })
  set(0, "TermToolOff", { fg = c.linenr, bg = card })
end
colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = colors })

return M
