-- Barra vertical de ferramentas na borda direita, como a do PhpStorm:
-- ícones empilhados que abrem/fecham os painéis; o painel aberto vira um card azulado.
local M = {}

local function neotree_open()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "neo-tree" then return true end
  end
  return false
end

local function aerial_open()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "aerial" then return true end
  end
  return false
end


-- Projeto, Commit e Structure dividem o mesmo espaço à direita: abrir um fecha os outros
local function close_slot(except)
  if except ~= "tree" and neotree_open() then pcall(vim.cmd, "Neotree close") end
  if except ~= "commit" then pcall(function() require("config.commit").close() end) end
  if except ~= "structure" and aerial_open() then pcall(vim.cmd, "AerialCloseAll") end
end
M.close_slot = close_slot

-- Volta para a janela de código (o Structure lista os símbolos do arquivo dela)
local function to_code()
  local main = require("config.panels").main_win()
  if main then vim.api.nvim_set_current_win(main) end
  return main
end

-- Ícones Codicons (traço fino, parecidos com os do PhpStorm)
M.items = {
  {
    icon = "\u{EA83}", name = "Projeto", key = "⌘1",
    active = neotree_open,
    toggle = function()
      if neotree_open() then return vim.cmd("Neotree close") end
      close_slot("tree")
      vim.cmd("Neotree filesystem show reveal")
    end,
  },
  {
    icon = "\u{EAFC}", name = "Commit", key = "⌘0",
    active = function() return require("config.commit").is_open() end,
    toggle = function()
      if not require("config.commit").is_open() then close_slot("commit") end
      require("config.commit").toggle()
    end,
  },
  {
    icon = "\u{EA91}", name = "Structure", key = "⌘7",
    active = aerial_open,
    toggle = function()
      if aerial_open() then return vim.cmd("AerialCloseAll") end
      close_slot("structure")
      if not to_code() then return vim.notify("Abra um arquivo para ver a estrutura", vim.log.levels.INFO, { title = "Structure" }) end
      require("aerial").open({ focus = false, direction = "right" })
    end,
  },
  { sep = true },
  {
    icon = "\u{EA6C}", name = "Problems", key = "⌘6",
    active = function() return require("config.problems").is_open() end,
    toggle = function() require("config.problems").toggle() end,
  },
  {
    icon = "\u{EB2C}", name = "Run", key = "",
    active = function() return require("config.run_panel").is_open() end,
    -- ícone verde enquanto algum comando do Run está rodando (mesmo com o painel fechado)
    badge = function()
      local run = package.loaded["config.run_panel"]
      if not run then return false end
      for _, t in ipairs(run.tabs) do if run.running(t) then return true end end
      return false
    end,
    toggle = function() require("config.run_panel").toggle() end,
  },
  {
    icon = "\u{EA85}", name = "Terminal", key = "⌥F12",
    active = function() return require("config.terminal").is_open() end,
    toggle = function() require("config.terminal").toggle() end,
  },
  {
    icon = "\u{EC10}", name = "Claude Code", key = "⌘⎋",
    active = function() return require("config.claude_panel").is_open() end,
    toggle = function() vim.cmd("ClaudeCode") end,
  },
  {
    icon = "\u{EA68}", name = "Git", key = "⌘9",
    active = function() return require("config.git_log").is_open() end,
    toggle = function() require("config.git_log").toggle() end,
  },
}

local ns = vim.api.nvim_create_namespace("activity_bar")
M.rows = {}

local function valid(w) return w and vim.api.nvim_win_is_valid(w) end

-- Ícone solto quando o painel está fechado; aberto, ganha um quadradinho arredondado
-- discreto. Os ícones da Nerd Font ocupam quase duas células, então o fundo é
-- ponta + ícone + folga + ponta, com uma coluna de margem de cada lado para o destaque
-- ficar no meio da faixa escura (sem encostar na borda da tela).
-- Item com algo rodando (badge, ex.: Run): o ícone fica verde.
local WIDTH = 6
local LCAP, RCAP = "\u{E0B6}", "\u{E0B4}" -- meias-luas (Ghostty desenha nativamente)

function M.render()
  if not (M.buf and vim.api.nvim_buf_is_valid(M.buf)) then return end
  -- Painéis (Projeto, Commit, Structure) em cima e ferramentas (Run, Terminal,
  -- Claude, Git) embaixo, com uma linha de folga entre os ícones
  local top, bottom = {}, {}
  local cur = top
  for i, it in ipairs(M.items) do
    if it.sep then cur = bottom else table.insert(cur, i) end
  end
  local lines, rows = { "" }, {}
  local function add(list)
    for _, i in ipairs(list) do
      table.insert(lines, " " .. LCAP .. M.items[i].icon .. " " .. RCAP .. " ")
      rows[#lines] = i
      table.insert(lines, "")
    end
  end
  add(top)
  local height = valid(M.win) and vim.api.nvim_win_get_height(M.win) or 0
  for _ = 1, math.max(height - #lines - #bottom * 2, 1) do table.insert(lines, "") end
  add(bottom)
  M.rows = rows
  vim.bo[M.buf].modifiable = true
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
  vim.bo[M.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(M.buf, ns, 0, -1)
  for row, i in pairs(rows) do
    local ok, on = pcall(M.items[i].active)
    on = ok and on
    local l = lines[row]
    local a = 1                    -- meia-lua esquerda (bytes)
    local b = a + #LCAP            -- miolo: ícone e folga
    local c = #l - 1 - #RCAP       -- meia-lua direita
    local ok_b, busy_ = pcall(M.items[i].badge or function() return false end)
    busy_ = ok_b and busy_
    local body = on and (busy_ and "ActivityBarActiveBusy" or "ActivityBarActive") or (busy_ and "ActivityBarItemBusy" or "ActivityBarItem")
    local cap = on and "ActivityBarCap" or "ActivityBarCapOff"
    vim.api.nvim_buf_set_extmark(M.buf, ns, row - 1, a, { end_col = b, hl_group = cap })
    vim.api.nvim_buf_set_extmark(M.buf, ns, row - 1, b, { end_col = c, hl_group = body })
    vim.api.nvim_buf_set_extmark(M.buf, ns, row - 1, c, { end_col = #l - 1, hl_group = cap })
  end
end

local function is_edge()
  if not valid(M.win) then return false end
  local pos = vim.api.nvim_win_get_position(M.win)
  local top, bottom = math.huge, 0
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == "" then
      local p = vim.api.nvim_win_get_position(w)
      top = math.min(top, p[1])
      bottom = math.max(bottom, p[1] + vim.api.nvim_win_get_height(w))
    end
  end
  return pos[2] + vim.api.nvim_win_get_width(M.win) >= vim.o.columns
    and pos[1] == top and pos[1] + vim.api.nvim_win_get_height(M.win) == bottom
end

local busy = false

local function style()
  local wo = vim.wo[M.win]
  wo.number, wo.relativenumber, wo.signcolumn, wo.statuscolumn = false, false, "no", ""
  wo.foldcolumn, wo.cursorline, wo.wrap, wo.winbar = "0", false, false, ""
  wo.winfixwidth = true
  wo.winhighlight = "Normal:ActivityBar,NormalNC:ActivityBar,EndOfBuffer:ActivityBar"
end

local function do_ensure()
  if not (M.buf and vim.api.nvim_buf_is_valid(M.buf)) then M.create_buf() end
  if not is_edge() then
    -- reposiciona na borda direita, na altura toda (fechar e abrir de novo preserva
    -- a largura dos outros painéis; "mover" a janela fazia o Neovim redistribuir tudo)
    if valid(M.win) then pcall(vim.api.nvim_win_close, M.win, true) end
    local cur = vim.api.nvim_get_current_win()
    M.win = vim.api.nvim_open_win(M.buf, false, { split = "right", win = -1, width = WIDTH })
    style()
    require("config.panels").mark(M.win, M.buf)
    if valid(cur) then vim.api.nvim_set_current_win(cur) end
  end
  M.render()
end

-- Protegida com pcall: um erro aqui nunca pode travar a barra.
function M.ensure()
  -- (abas de diff e de Compare ficam sem a barra: vim.t.no_activity_bar)
  if busy or not M.enabled or vim.t.rollback_diff or vim.t.no_activity_bar then return end
  busy = true
  local ok, err = pcall(do_ensure)
  busy = false
  if not ok then M.last_error = err end
end

function M.create_buf()
  M.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M.buf].bufhidden = "hide"
  vim.bo[M.buf].filetype = "activity_bar"
end

-- Clique na barra: tratado antes do Neovim mover o foco, então a barra nunca fica
-- com o cursor (era isso que travava o menu depois de alguns cliques)
local function on_mouse()
  local pos = vim.fn.getmousepos()
  if not (valid(M.win) and pos.winid == M.win) then return "<LeftMouse>" end
  local i = M.rows[pos.line]
  if i then
    vim.schedule(function()
      local ok, err = pcall(M.items[i].toggle)
      if not ok then vim.notify(tostring(err), vim.log.levels.WARN, { title = M.items[i].name }) end
      vim.schedule(M.ensure)
    end)
  end
  return ""
end

function M.setup()
  -- Não abre em Neovims "de passagem" (mensagem de commit do git, Neovim dentro do terminal etc.)
  if vim.env.NVIM or vim.g.started_by_firenvim then return end
  local arg = vim.fn.argv(0) or ""
  if type(arg) == "string" and arg:match("COMMIT_EDITMSG") or arg:match("git%-rebase%-todo") or arg:match("MERGE_MSG") then return end
  M.enabled = true
  vim.keymap.set({ "n", "i", "v", "t" }, "<LeftMouse>", on_mouse, { expr = true, desc = "Clique (barra de ferramentas)" })
  -- A rodinha do mouse em cima da barra não rola nada (antes ela rolava os ícones para fora)
  for _, key in ipairs({ "<ScrollWheelUp>", "<ScrollWheelDown>", "<ScrollWheelLeft>", "<ScrollWheelRight>" }) do
    vim.keymap.set({ "n", "i", "v", "t" }, key, function()
      return valid(M.win) and vim.fn.getmousepos().winid == M.win and "" or key
    end, { expr = true })
  end
  local group = vim.api.nvim_create_augroup("activity_bar", { clear = true })
  -- E se rolar por qualquer outro caminho, volta para o topo
  vim.api.nvim_create_autocmd("WinScrolled", {
    group = group,
    callback = function()
      if not valid(M.win) then return end
      local view = vim.api.nvim_win_call(M.win, vim.fn.winsaveview)
      if view.topline ~= 1 or view.leftcol ~= 0 then
        vim.api.nvim_win_call(M.win, function() vim.fn.winrestview({ topline = 1, leftcol = 0 }) end)
      end
    end,
  })
  -- Se o foco cair na barra por outro caminho (Ctrl-w, :wincmd), devolve para o código
  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      if valid(M.win) and vim.api.nvim_get_current_win() == M.win then
        vim.schedule(function()
          if vim.api.nvim_get_current_win() ~= M.win then return end
          local back = valid(M.prev_win) and M.prev_win or require("config.panels").main_win()
          if back then vim.api.nvim_set_current_win(back) end
        end)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "WinNew", "WinClosed", "VimResized", "WinResized", "BufWinEnter" }, {
    group = group, callback = function() vim.schedule(M.ensure) end,
  })
  -- Lembra a última janela "de verdade" para devolver o foco após um clique
  vim.api.nvim_create_autocmd("WinLeave", {
    group = group,
    callback = function()
      local w = vim.api.nvim_get_current_win()
      if w ~= M.win then M.prev_win = w end
    end,
  })
  -- Ao sair pelo último arquivo, fecha a barra e os painéis para o :q funcionar.
  -- Se o :q falhar (arquivo não salvo etc.), a barra volta sozinha.
  vim.api.nvim_create_autocmd("QuitPre", {
    group = group,
    callback = function()
      local normal = 0
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local b = vim.api.nvim_win_get_buf(w)
        if vim.api.nvim_win_get_config(w).relative == "" and vim.bo[b].buftype == "" then normal = normal + 1 end
      end
      if normal <= 1 and vim.bo.buftype == "" then
        busy = true
        if valid(M.win) then pcall(vim.api.nvim_win_close, M.win, true) end
        pcall(function() require("config.commit").close() end)
        pcall(function() require("config.terminal").hide() end)
        pcall(vim.cmd, "Neotree close")
        pcall(vim.cmd, "AerialCloseAll")
        busy = false
        vim.defer_fn(function() if M.enabled then M.ensure() end end, 50)
      end
    end,
  })
  vim.schedule(M.ensure)
end

local function colors()
  local ok, c = pcall(require, "config.palette")
  if not ok then return end
  local set = vim.api.nvim_set_hl
  -- Faixa no fundo das ilhas (canvas), ícones cinza-claro; o painel aberto ganha só
  -- um quadradinho arredondado cinza e o ícone clareia, sem cor de destaque
  local strip, active = c.canvas, "#2B2D31"
  set(0, "ActivityBar", { fg = c.fg_dim, bg = strip })
  set(0, "ActivityBarItem", { fg = "#9DA0A8", bg = strip })
  set(0, "ActivityBarCapOff", { fg = strip, bg = strip })
  set(0, "ActivityBarActive", { fg = "#DFE1E5", bg = active })
  set(0, "ActivityBarCap", { fg = active, bg = strip })
  set(0, "ActivityBarItemBusy", { fg = c.hint, bg = strip })
  set(0, "ActivityBarActiveBusy", { fg = c.hint, bg = active })
end
colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = colors })

return M
