-- Painéis "presos": a janela de um painel (Commit, terminal, barra lateral) só mostra o
-- próprio conteúdo. Se um arquivo tentar abrir dentro dela (busca, clique numa aba,
-- ir para definição...), o painel volta ao normal e o arquivo abre na janela de código.
local M = {}

-- Marca uma janela como painel. own = buffer fixo; kind = "terminal"/"run" aceita as abas daquele painel
function M.mark(win, own, kind)
  if not (win and vim.api.nvim_win_is_valid(win)) then return end
  vim.w[win].panel_buf = own
  vim.w[win].panel_kind = kind or "fixed"
end

function M.is_panel(win)
  return vim.w[win].panel_kind ~= nil
end

local SPECIAL_FT = { ["neo-tree"] = true, aerial = true, activity_bar = true, snacks_dashboard = false }

-- Janela de código: não flutuante, não painel, sem painel lateral
function M.main_win()
  local best
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == "" and not M.is_panel(w) then
      local b = vim.api.nvim_win_get_buf(w)
      local bt, ft = vim.bo[b].buftype, vim.bo[b].filetype
      if not SPECIAL_FT[ft] and (bt == "" or ft == "snacks_dashboard") then
        if w == vim.api.nvim_get_current_win() then return w end
        best = best or w
      end
    end
  end
  return best
end

-- painéis de terminal (config/term_panel.lua) e o módulo de cada um
local TERM = { terminal = "config.terminal", run = "config.run_panel", claude = "config.claude_panel" }

local function accepts(win, buf)
  local kind = vim.w[win].panel_kind
  if TERM[kind] then return vim.b[buf].term_tab == kind end
  return vim.w[win].panel_buf == buf
end

local function restore(win)
  local kind = vim.w[win].panel_kind
  if TERM[kind] then
    local t = require(TERM[kind])
    local tab = t.tabs[t.cur]
    if tab and vim.api.nvim_buf_is_valid(tab.buf) then return pcall(vim.api.nvim_win_set_buf, win, tab.buf) end
    return pcall(vim.api.nvim_win_close, win, true)
  end
  local own = vim.w[win].panel_buf
  if own and vim.api.nvim_buf_is_valid(own) then return pcall(vim.api.nvim_win_set_buf, win, own) end
  pcall(vim.api.nvim_win_close, win, true)
end

vim.api.nvim_create_autocmd("BufWinEnter", {
  group = vim.api.nvim_create_augroup("panels_guard", { clear = true }),
  callback = function(ev)
    local buf = ev.buf
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      if M.is_panel(win) and not accepts(win, buf) then
        vim.schedule(function()
          if not vim.api.nvim_win_is_valid(win) then return end
          local cursor = vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_get_cursor(win) or nil
          restore(win)
          -- arquivo de verdade: abre na janela de código
          if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "" then
            local main = M.main_win()
            if not main then
              main = vim.api.nvim_open_win(buf, true, { split = "left", win = vim.api.nvim_win_is_valid(win) and win or -1 })
            end
            vim.api.nvim_set_current_win(main)
            vim.api.nvim_win_set_buf(main, buf)
            if cursor then pcall(vim.api.nvim_win_set_cursor, main, cursor) end
          end
        end)
      end
    end
  end,
})

-- Listas laterais (Projeto, Structure, Commit) e painéis de terminal não rolam além do último item:
-- o fim da lista para no pé da janela, em vez de subir até sobrar só tela vazia
local NO_OVERSCROLL = { ["neo-tree"] = true, aerial = true, commit_list = true }

vim.api.nvim_create_autocmd("WinScrolled", {
  group = vim.api.nvim_create_augroup("panels_no_overscroll", { clear = true }),
  callback = function()
    for id in pairs(vim.v.event) do
      local win = tonumber(id)
      if win and vim.api.nvim_win_is_valid(win) then
        local buf = vim.api.nvim_win_get_buf(win)
        -- (também os painéis de terminal: Claude, Terminal, Run)
        if NO_OVERSCROLL[vim.bo[buf].filetype] or vim.b[buf].term_tab then
          vim.api.nvim_win_call(win, function()
            local max_top = math.max(1, vim.api.nvim_buf_line_count(buf) - vim.api.nvim_win_get_height(win) + 1)
            local view = vim.fn.winsaveview()
            if view.topline > max_top then
              view.topline = max_top
              vim.fn.winrestview(view)
            end
          end)
        end
      end
    end
  end,
})

return M
