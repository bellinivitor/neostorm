-- Painel Run: cada comando do Run Anything (Cmd+Shift+X) roda numa aba própria.
--   Run  ( ▶ npm run serve × ) ( ✓ php artisan migrate × )        ( ⟳ Rerun ) ( ■ Stop )
-- Quando o processo termina a aba continua lá com a saída, marcada com ✓ ou ✗.
require("config.terminal") -- cores dos painéis

return require("config.term_panel")({
  id = "run",
  title = "Run",
  module = "config.run_panel",
  other = "config.terminal",
  keep_on_exit = true,
  toolbar = true,
  tab_icon = function(t)
    if t.stopped then return "\u{F04DB}", "TermTabStopped" end -- ■ parado
    if t.code == nil then return "\u{F040A}", "TermTabRun" end -- ▶ rodando
    if t.code == 0 then return "\u{F012C}", "TermTabOk" end -- ✓
    return "\u{F0156}", "TermTabFail" -- ✗
  end,
})
