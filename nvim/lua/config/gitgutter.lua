-- Indicador de alterações do git no estilo PhpStorm:
--   coluna = [diagnóstico ou ▶ de teste] [número da linha] [barra do git]
--   clicar na barra abre um menu com "Ver diff" e "Rollback"
local M = {}

-- ---------------------------------------------------------------------------
-- Coluna da esquerda (statuscolumn)
-- ---------------------------------------------------------------------------
local ns_names = {}
local function ns_name(id)
  if not ns_names[id] then
    for name, nid in pairs(vim.api.nvim_get_namespaces()) do ns_names[nid] = name end
  end
  return ns_names[id] or ""
end

function M.statuscolumn()
  local win = vim.g.statusline_winid
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= "" then return "" end

  local lnum = vim.v.lnum
  local diag, git = "  ", " "
  local diag_prio, git_prio = -1, -1
  local marks = vim.api.nvim_buf_get_extmarks(buf, -1, { lnum - 1, 0 }, { lnum - 1, -1 }, { details = true, type = "sign" })
  for _, m in ipairs(marks) do
    local d = m[4]
    if d.sign_text then
      local text = vim.trim(d.sign_text)
      local prio = d.priority or 0
      if ns_name(d.ns_id):find("^gitsigns_signs") then
        if prio > git_prio then
          git_prio = prio
          git = "%#" .. (d.sign_hl_group or "SignColumn") .. "#" .. vim.fn.strcharpart(text, 0, 1) .. "%*"
        end
      elseif prio > diag_prio then
        diag_prio = prio
        diag = "%#" .. (d.sign_hl_group or "SignColumn") .. "#" .. text .. string.rep(" ", 2 - vim.fn.strdisplaywidth(text)) .. "%*"
        -- ▶ dos testes (config/tests.lua): clicável, roda o teste da linha
        if ns_name(d.ns_id) == "pest_tests" then diag = "%@v:lua.TestGutterClick@" .. diag .. "%T" end
        -- ícone de rota (config/endpoints.lua): clicável, vai para o controller
        if ns_name(d.ns_id) == "route_targets" then diag = "%@v:lua.RouteGutterClick@" .. diag .. "%T" end
      end
    end
  end

  -- Linhas quebradas (wrap) e linhas virtuais não repetem o número nem a barra
  local num
  if vim.v.virtnum ~= 0 then
    num = ""
    diag = "  "
  elseif vim.wo[win].relativenumber and vim.v.relnum ~= 0 then
    num = tostring(vim.v.relnum)
  else
    num = tostring(lnum)
  end
  local num_hl = vim.v.relnum == 0 and "%#CursorLineNr#" or "%#LineNr#"

  return diag .. "%=" .. num_hl .. num .. "%* " .. "%@v:lua.GitGutterClick@" .. git .. "%T "
end

-- ---------------------------------------------------------------------------
-- Hunks
-- ---------------------------------------------------------------------------
local function hunk_at(buf, lnum)
  local ok, hunks = pcall(require("gitsigns").get_hunks, buf)
  if not ok or not hunks then return nil end
  for _, h in ipairs(hunks) do
    local first = math.max(h.added.start, 1)
    local last = first + math.max(h.added.count, 1) - 1
    if lnum >= first and lnum <= last then return h end
  end
end

local function goto_line(win, lnum)
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_cursor(win, { lnum, 0 })
end

function M.diff(win, lnum)
  goto_line(win, lnum)
  require("gitsigns").preview_hunk()
end

function M.rollback(win, lnum)
  goto_line(win, lnum)
  require("gitsigns").reset_hunk()
end

-- ---------------------------------------------------------------------------
-- Menu (Ver diff / Rollback)
-- ---------------------------------------------------------------------------
function M.menu(opts)
  opts = opts or {}
  local win = opts.win or vim.api.nvim_get_current_win()
  local lnum = opts.lnum or vim.api.nvim_win_get_cursor(win)[1]
  local buf = vim.api.nvim_win_get_buf(win)
  if not hunk_at(buf, lnum) then
    vim.notify("Nenhuma alteração nesta linha", vim.log.levels.INFO)
    return
  end
  require("config.popup_menu").open({
    { label = "\u{F0EC6}  Ver diff", key = "d", run = function() M.diff(win, lnum) end },
    { label = "\u{F054C}  Rollback", key = "r", hint = "⌥⌘Z", run = function() M.rollback(win, lnum) end },
  }, { mouse = opts.mouse })
end

-- Chamado pelo clique na barra do git (%@...@ da statuscolumn)
function _G.GitGutterClick(_, clicks, button)
  if button ~= "l" then return end
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or pos.line == 0 then return end
  vim.schedule(function() M.menu({ win = pos.winid, lnum = pos.line, mouse = true }) end)
end

return M
