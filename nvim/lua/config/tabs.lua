-- Abas de arquivos em formato de card (pílulas com cantos arredondados):
--   ╭ php Ticket.php × ╮ ╭ vue Show.vue ● ╮
-- As pontas usam os semicírculos do Powerline ( ), que o Ghostty desenha
-- na altura inteira da célula, então o card fica fechado mesmo com o
-- adjust-cell-height. × fecha, ● indica arquivo não salvo, clique do meio fecha.
local M = {}

M.L = "\u{E0B6}" --
M.R = "\u{E0B4}" --

local function listed()
  local out = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buflisted then
      local name = vim.api.nvim_buf_get_name(b)
      if not (name == "" and not vim.bo[b].modified) and vim.bo[b].buftype == "" then
        table.insert(out, b)
      end
    end
  end
  return out
end

-- Nomes iguais (dois index.vue) ganham a pasta: index.vue · Tickets
local function labels(bufs)
  local base, count = {}, {}
  for _, b in ipairs(bufs) do
    local name = vim.api.nvim_buf_get_name(b)
    base[b] = name == "" and "Sem nome" or vim.fn.fnamemodify(name, ":t")
    count[base[b]] = (count[base[b]] or 0) + 1
  end
  local out = {}
  for _, b in ipairs(bufs) do
    out[b] = base[b]
    if count[base[b]] > 1 then
      out[b] = base[b] .. " \u{00B7} " .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":h:t")
    end
  end
  return out
end

-- Ícone colorido do devicons, com o fundo do card
local icon_hl_cache = {}
local function icon_for(buf, active)
  local ok, devicons = pcall(require, "nvim-web-devicons")
  if not ok then return nil end
  local name = vim.api.nvim_buf_get_name(buf)
  local icon, color = devicons.get_icon_color(vim.fn.fnamemodify(name, ":t"), vim.fn.fnamemodify(name, ":e"), { default = true })
  if not icon then return nil end
  local group = "TabCardIcon" .. (active and "Sel" or "") .. color:gsub("#", "")
  if not icon_hl_cache[group] then
    local card = vim.api.nvim_get_hl(0, { name = active and "TabCardSel" or "TabCard" })
    vim.api.nvim_set_hl(0, group, { fg = active and color or vim.api.nvim_get_hl(0, { name = "TabCard" }).fg, bg = card.bg })
    icon_hl_cache[group] = true
  end
  return icon, group
end

--- Monta um card. parts: { icon, icon_hl, text, tail, tail_hl, click, close_click, active }
--- Retorna a string da statusline e a largura visível.
function M.card(p)
  local sfx = p.active and "Sel" or ""
  local body, cap = "%#TabCard" .. sfx .. "#", "%#TabCardCap" .. sfx .. "#"
  local s, w = cap .. M.L, 1
  if p.click then s = s .. p.click end
  s = s .. body .. " "
  w = w + 1
  if p.icon then
    s = s .. "%#" .. p.icon_hl .. "#" .. p.icon .. " " .. body
    w = w + vim.api.nvim_strwidth(p.icon) + 1
  end
  s = s .. p.text:gsub("%%", "%%%%") .. " "
  w = w + vim.api.nvim_strwidth(p.text) + 1
  if p.click then s = s .. "%X" end
  if p.tail then
    s = s .. (p.close_click or "") .. "%#" .. p.tail_hl .. sfx .. "#" .. p.tail .. " " .. (p.close_click and "%X" or "")
    w = w + vim.api.nvim_strwidth(p.tail) + 1
  end
  s = s .. cap .. M.R
  w = w + 1
  return s, w
end

-- Largura ocupada pela árvore do projeto (e a barra de ferramentas) na direita (para o "Projeto" ficar em cima dela)
local function tree_width()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "neo-tree" and vim.api.nvim_win_get_config(win).relative == "" then
      -- a árvore fica na metade direita, antes da barra de ferramentas:
      -- reserva tudo dali até a borda, começando no separador vertical
      local col = vim.api.nvim_win_get_position(win)[2]
      if col > vim.o.columns / 2 then return vim.o.columns - col + 1 end
    end
  end
  return 0
end

-- Se a expressão da tabline der erro, o Neovim apaga a opção e volta para a barra
-- padrão ("3 ~/w/t/t/a/M/Arquivo.php"). Por isso o desenho roda protegido: em caso de
-- erro mostra só o nome do arquivo e guarda o motivo em vim.g.tabs_error.
function M.render()
  local ok, out = pcall(M.draw)
  if ok then return out end
  vim.g.tabs_error = tostring(out)
  return "%#TabCardFill#  %t"
end

function M.draw()
  local bufs = listed()
  local names = labels(bufs)
  local cur = vim.api.nvim_get_current_buf()
  local cards, cur_i = {}, 1
  for i, b in ipairs(bufs) do
    local active = b == cur
    if active then cur_i = i end
    local icon, icon_hl = icon_for(b, active)
    local modified = vim.bo[b].modified
    local s, w = M.card({
      active = active,
      icon = icon, icon_hl = icon_hl,
      text = names[b],
      tail = modified and "\u{25CF}" or "\u{00D7}",
      tail_hl = modified and "TabCardModified" or "TabCardClose",
      click = "%" .. b .. "@v:lua.TabCardClick@",
      close_click = "%" .. b .. "@v:lua.TabCardClose@",
    })
    cards[i] = { s = s, w = w + 1 } -- +1 do espaço entre cards
  end

  local tree = tree_width()
  local avail = vim.o.columns - tree - 1
  -- Se não couber tudo, mantém a aba atual visível e vai abrindo para os lados
  local first, last, used = cur_i, cur_i, cards[cur_i] and cards[cur_i].w or 0
  local grew = true
  while grew do
    grew = false
    if cards[last + 1] and used + cards[last + 1].w <= avail then
      last = last + 1; used = used + cards[last].w; grew = true
    end
    if cards[first - 1] and used + cards[first - 1].w <= avail then
      first = first - 1; used = used + cards[first].w; grew = true
    end
  end

  local out = { "%#TabCardFill# " }
  if first > 1 then out[1] = "%#TabCardMore#\u{2039}" end
  for i = first, last do table.insert(out, cards[i].s .. "%#TabCardFill# ") end
  if last < #cards then table.insert(out, "%#TabCardMore#\u{203A}") end
  table.insert(out, "%#TabCardFill#%=")
  if tree > 0 then
    table.insert(out, "%#TabCardTree#\u{2502} Projeto" .. string.rep(" ", tree - 9))
  end
  return table.concat(out)
end

function _G.TabCardClick(buf, _, button)
  vim.schedule(function()
    if button == "m" then return M.delete(buf) end
    if vim.api.nvim_buf_is_valid(buf) then
      -- não abre o arquivo dentro do painel de terminal / árvore
      if vim.bo.buftype ~= "" or vim.bo.filetype == "neo-tree" then vim.cmd("wincmd p") end
      vim.api.nvim_set_current_buf(buf)
    end
  end)
end

function _G.TabCardClose(buf) vim.schedule(function() M.delete(buf) end) end

function M.delete(buf)
  if _G.Snacks then Snacks.bufdelete(buf) else pcall(vim.cmd.bdelete, buf) end
end

-- Cmd+Shift+[ / ] : aba anterior / próxima
function M.cycle(step)
  local bufs = listed()
  if #bufs == 0 then return end
  local cur = vim.api.nvim_get_current_buf()
  local idx = 0
  for i, b in ipairs(bufs) do if b == cur then idx = i end end
  vim.api.nvim_set_current_buf(bufs[((idx - 1 + step) % #bufs) + 1])
end

-- ---------------------------------------------------------------------------
-- Cores: o card ativo tem fundo azulado (como a aba "Local" do PhpStorm),
-- os outros são cards discretos um tom acima do fundo
-- ---------------------------------------------------------------------------
function M.colors()
  local c = require("config.palette")
  local card, sel = "#26282C", "#2A3650"
  local set = vim.api.nvim_set_hl
  icon_hl_cache = {}
  set(0, "TabCardFill", { bg = c.bg })
  set(0, "TabCard", { fg = c.fg_faint, bg = card })
  set(0, "TabCardCap", { fg = card, bg = c.bg })
  set(0, "TabCardSel", { fg = "#DFE1E5", bg = sel })
  set(0, "TabCardCapSel", { fg = sel, bg = c.bg })
  set(0, "TabCardClose", { fg = c.linenr, bg = card })
  set(0, "TabCardCloseSel", { fg = c.fg_dim, bg = sel })
  set(0, "TabCardModified", { fg = c.fg_dim, bg = card })
  set(0, "TabCardModifiedSel", { fg = c.accent, bg = sel })
  set(0, "TabCardMore", { fg = c.fg_dim, bg = c.bg })
  set(0, "TabCardTree", { fg = c.fg_dim, bg = c.bg })
  set(0, "TabLineFill", { link = "TabCardFill" })
end

function M.setup()
  M.colors()
  vim.api.nvim_create_autocmd("ColorScheme", { callback = M.colors })
  vim.o.showtabline = 2
  M.expr = "%!v:lua.require'config.tabs'.render()"
  vim.o.tabline = M.expr
  -- Garantia extra: se algo apagar a tabline, ela volta na próxima troca de arquivo/janela
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "FocusGained" }, {
    callback = function()
      if vim.o.tabline ~= M.expr then vim.o.showtabline, vim.o.tabline = 2, M.expr end
    end,
  })
  -- o ● de não salvo aparece na hora
  vim.api.nvim_create_autocmd({ "BufModifiedSet", "BufAdd", "BufDelete", "WinResized" }, {
    callback = function() vim.schedule(function() vim.cmd.redrawtabline() end) end,
  })
end

return M
