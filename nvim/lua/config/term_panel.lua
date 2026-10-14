-- Painel embaixo com abas de terminal em cards (mesmo visual de config/tabs.lua).
-- Usado por dois painéis, que dividem o mesmo espaço (abrir um esconde o outro):
--   Terminal  ( Local × ) ( ✳ Claude Code × ) ( + )            → config/terminal.lua
--   Run       ( ▶ npm run serve × ) ( ✓ php artisan migrate × )   ( ⟳ Rerun ) ( ■ Stop )  → config/run_panel.lua
-- cfg = { id, title, module, other, new_button, toolbar, keep_on_exit, layout,
--         hide_tabs (painel de uma aba só), winbar_right() -> texto no canto direito,
--         tab_icon(t) -> icon, hl }
return function(cfg)
  local M = {}

  M.id = cfg.id
  M.tabs = {}         -- { { buf, name, claude, spec, code, stopped } }
  M.cur = 0           -- índice da aba visível
  M.win = nil         -- janela do painel
  M.layout = cfg.layout or "bottom" -- bottom | right | float

  local layouts = {
    bottom = { size = 0.3 },
    right = { size = 0.4 },
    float = { width = 0.85, height = 0.8 },
  }

  local G = cfg.id:sub(1, 1):upper() .. cfg.id:sub(2) -- prefixo das funções de clique

  local function valid_win() return M.win and vim.api.nvim_win_is_valid(M.win) end
  local function index_of(buf)
    for i, t in ipairs(M.tabs) do if t.buf == buf then return i end end
  end

  function M.running(t)
    t = t or M.tabs[M.cur]
    return t and t.code == nil and not t.stopped
  end

  -- -------------------------------------------------------------------------
  -- Barra de abas (winbar clicável)
  -- -------------------------------------------------------------------------
  function M.winbar()
    local card = require("config.tabs").card
    local parts = { "%#TermTabTitle# " .. cfg.title .. " %<" } -- se faltar espaço, corta as abas e não o título
    for i, t in ipairs(cfg.hide_tabs and {} or M.tabs) do
      local active = i == M.cur
      local icon, hl = cfg.tab_icon(t)
      local s = card({
        active = active,
        icon = icon, icon_hl = hl .. (active and "Sel" or ""),
        text = t.name,
        tail = "\u{00D7}", tail_hl = "TabCardClose",
        click = "%" .. i .. "@v:lua." .. G .. "TabSelect@",
        close_click = "%" .. i .. "@v:lua." .. G .. "TabClose@",
      })
      table.insert(parts, s .. "%#TermTabBar# ")
    end
    if cfg.new_button then
      table.insert(parts, "%@v:lua." .. G .. "TabNew@" .. card({ text = "+" }) .. "%X%#TermTabBar#")
    end
    if cfg.toolbar and #M.tabs > 0 then
      -- Rerun sempre disponível; Stop só acende enquanto o processo roda
      local running = M.running()
      table.insert(parts, "%=")
      table.insert(parts, "%@v:lua." .. G .. "TabRerun@" .. card({ icon = "\u{F0450}", icon_hl = "TermToolRerun", text = "Rerun" }) .. "%X%#TermTabBar# ")
      table.insert(parts, "%@v:lua." .. G .. "TabStop@" .. card({
        icon = "\u{F04DB}", icon_hl = running and "TermToolStop" or "TermToolOff", text = "Stop",
      }) .. "%X%#TermTabBar# ")
    end
    if cfg.winbar_right then
      local ok, right = pcall(cfg.winbar_right)
      if ok and right and right ~= "" then table.insert(parts, "%#TermTabBar#%=" .. right) end
    end
    return table.concat(parts)
  end

  _G[G .. "TabSelect"] = function(i) vim.schedule(function() M.select(i) end) end
  _G[G .. "TabClose"] = function(i) vim.schedule(function() M.close(i) end) end
  _G[G .. "TabNew"] = function() vim.schedule(function() M.new() end) end
  _G[G .. "TabRerun"] = function() vim.schedule(function() M.rerun() end) end
  _G[G .. "TabStop"] = function() vim.schedule(function() M.stop() end) end

  local function redraw()
    if valid_win() then vim.cmd("redrawstatus!") end
    -- a barra lateral mostra se algo está rodando (ícone verde no Run), mesmo com o painel fechado
    pcall(function() require("config.activity_bar").render() end)
  end
  M.redraw = redraw

  -- -------------------------------------------------------------------------
  -- Janela do painel
  -- -------------------------------------------------------------------------
  local function style_win(win)
    local wo = vim.wo[win]
    wo.number = false
    wo.relativenumber = false
    wo.signcolumn = "no"
    wo.statuscolumn = ""
    wo.foldcolumn = "0"
    wo.cursorline = false
    wo.winfixheight = true
    wo.winfixwidth = true
    wo.winbar = "%!v:lua.require'" .. cfg.module .. "'.winbar()"
    wo.winhighlight = "Normal:TermPanel,NormalNC:TermPanel,WinBar:TermTabBar,WinBarNC:TermTabBar"
    -- caminho:linha clicável (stack traces, testes que falham)
    pcall(function() require("config.stack_links").attach(win, vim.api.nvim_win_get_buf(win)) end)
  end

  local function other()
    if not cfg.other then return nil end
    local ok, o = pcall(require, cfg.other)
    return ok and o or nil
  end

  local function open_win(buf)
    if valid_win() then
      vim.api.nvim_win_set_buf(M.win, buf)
      return M.win
    end
    -- Terminal e Run ocupam o mesmo lugar: abre um, esconde o outro
    local o = other()
    if o and o.is_open() then o.hide() end
    -- o painel Problems também fica embaixo
    local problems = package.loaded["config.problems"]
    if problems and problems.is_open() and M.layout == "bottom" then problems.close() end
    local git_log = package.loaded["config.git_log"]
    if git_log and git_log.is_open() and M.layout == "bottom" then git_log.close() end
    local L = layouts[M.layout]
    if M.layout == "float" then
      local w = math.floor(vim.o.columns * L.width)
      local h = math.floor(vim.o.lines * L.height)
      M.win = vim.api.nvim_open_win(buf, true, {
        relative = "editor", width = w, height = h,
        row = math.floor((vim.o.lines - h) / 2) - 1, col = math.floor((vim.o.columns - w) / 2),
        border = "rounded", style = "minimal",
      })
    elseif M.layout == "right" then
      -- Logo à direita da janela de código (ou do dashboard), antes da árvore do Projeto
      -- e da barra de ferramentas, que continuam encostadas na borda
      local anchor = require("config.panels").main_win() or -1
      M.win = vim.api.nvim_open_win(buf, true, { split = "right", win = anchor, width = math.floor(vim.o.columns * L.size) })
    else
      M.win = vim.api.nvim_open_win(buf, true, { split = "below", win = -1, height = math.floor(vim.o.lines * L.size) })
    end
    style_win(M.win)
    require("config.panels").mark(M.win, nil, cfg.id)
    pcall(function() require("config.activity_bar").ensure() end)
    return M.win
  end

  function M.is_open() return valid_win() end

  function M.hide()
    if valid_win() then
      if not pcall(vim.api.nvim_win_close, M.win, true) then
        -- era a última janela: em vez de abrir outra, troca para um buffer vazio
        pcall(vim.api.nvim_win_set_buf, M.win, vim.api.nvim_create_buf(true, false))
      end
    end
    M.win = nil
  end

  -- -------------------------------------------------------------------------
  -- Abas
  -- -------------------------------------------------------------------------
  local function unique_name(base)
    local n, name = 1, base
    local function taken(x)
      for _, t in ipairs(M.tabs) do if t.name == x then return true end end
    end
    while taken(name) do n = n + 1; name = base .. " (" .. n .. ")" end
    return name
  end

  local function buffer_keys(buf, is_claude)
    local function map(lhs, rhs, desc) vim.keymap.set("t", lhs, rhs, { buffer = buf, desc = desc }) end
    -- Ctrl+k volta para o código sem fechar o painel
    map("<C-k>", "<cmd>wincmd p<cr>", "Ir para o editor")
    vim.keymap.set("n", "<D-w>", function() M.close() end, { buffer = buf, desc = "Fechar aba" })
    -- Clique simples no terminal volta a digitar. Programas que não usam o mouse (como o Claude
    -- Code) fazem o Neovim sair do modo de digitação a cada clique; sem isso, clicar no painel
    -- deixava o foco nele, mas sem conseguir escrever. (Arrastar para selecionar e copiar
    -- continua: aí fica em modo visual e este atalho não roda.)
    vim.keymap.set("n", "<LeftRelease>", function()
      local pos = vim.fn.getmousepos()
      if pos.winid ~= 0 and vim.api.nvim_win_get_buf(pos.winid) == buf and M.running() then
        vim.api.nvim_set_current_win(pos.winid)
        vim.cmd.startinsert()
      end
    end, { buffer = buf, desc = "Clique: voltar a digitar" })
    if not is_claude then
      -- Esc duas vezes: sai do modo de digitação (para rolar e copiar a saída)
      -- (no Claude Code, Esc e Esc Esc são do próprio Claude)
      map("<Esc><Esc>", [[<C-\><C-n>]], "Modo normal no terminal")
    end
  end

  -- Cria o buffer e o processo de uma aba (usado ao abrir e no Rerun)
  local function start(tab)
    local spec = tab.spec
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "hide"
    tab.buf, tab.code, tab.stopped = buf, nil, nil
    open_win(buf)
    vim.api.nvim_set_current_win(M.win)
    vim.fn.jobstart(spec.cmd or { vim.o.shell }, {
      term = true,
      cwd = spec.cwd or vim.fn.getcwd(),
      -- o `php` do terminal é o do projeto (versão do Herd), não o global
      env = require("config.project_php").env(spec.cwd or vim.fn.getcwd(), spec.env),
      on_exit = function(_, code)
        vim.schedule(function()
          -- quem abriu a aba pode querer saber o resultado (ex.: testes marcam ✓/✗ na margem)
          if spec.on_exit and tab.buf == buf then pcall(spec.on_exit, code) end
          if tab.buf ~= buf or not index_of(buf) then return end -- já foi reiniciada/fechada
          if cfg.keep_on_exit then
            -- a aba fica com ✓/✗; sai do modo de digitação para uma tecla não fechar o buffer
            tab.code = code
            if vim.api.nvim_get_current_buf() == buf then vim.cmd.stopinsert() end
            return redraw()
          end
          M.close(index_of(buf), { keep_job = true })
        end)
      end,
    })
    vim.bo[buf].buflisted = false
    vim.b[buf].term_tab = cfg.id
    buffer_keys(buf, spec.claude)
    return buf
  end

  --- Abre uma aba nova. opts: { name, cmd, env, cwd, claude, focus, on_exit(code) }
  function M.new(opts)
    opts = opts or {}
    local prev_win = vim.api.nvim_get_current_win()
    local tab = { name = unique_name(opts.name or "Local"), claude = opts.claude, spec = opts }
    table.insert(M.tabs, tab)
    M.cur = #M.tabs
    start(tab)
    redraw()
    if opts.focus == false then
      if vim.api.nvim_win_is_valid(prev_win) then vim.api.nvim_set_current_win(prev_win) end
    else
      vim.cmd.startinsert()
    end
    return tab
  end

  function M.select(i, focus)
    local t = M.tabs[i]
    if not t then return end
    M.cur = i
    open_win(t.buf)
    redraw()
    if focus ~= false then
      vim.api.nvim_set_current_win(M.win)
      if M.running(t) or not cfg.keep_on_exit then vim.cmd.startinsert() end
    end
  end

  function M.close(i, opts)
    opts = opts or {}
    i = i or M.cur
    local t = M.tabs[i]
    if not t then return end
    table.remove(M.tabs, i)
    if #M.tabs == 0 then
      M.cur = 0
      M.hide()
    else
      M.cur = math.min(i, #M.tabs)
      if valid_win() then M.select(M.cur, false) end
    end
    if not opts.keep_job then
      pcall(vim.fn.jobstop, vim.b[t.buf].terminal_job_id)
    end
    if vim.api.nvim_buf_is_valid(t.buf) then pcall(vim.api.nvim_buf_delete, t.buf, { force = true }) end
    redraw()
  end

  -- Para o processo da aba atual (a aba fica, marcada como parada)
  function M.stop(i)
    local t = M.tabs[i or M.cur]
    if not (t and M.running(t)) then return end
    t.stopped = true
    pcall(vim.fn.jobstop, vim.b[t.buf].terminal_job_id)
    redraw()
  end

  -- Roda de novo o comando da aba atual, na mesma aba
  function M.rerun(i)
    i = i or M.cur
    local t = M.tabs[i]
    if not t then return end
    local old = t.buf
    if M.running(t) then pcall(vim.fn.jobstop, vim.b[old].terminal_job_id) end
    M.cur = i
    start(t)
    if vim.api.nvim_buf_is_valid(old) then pcall(vim.api.nvim_buf_delete, old, { force = true }) end
    redraw()
  end

  function M.find(name)
    for i, t in ipairs(M.tabs) do if t.name == name then return i end end
  end

  function M.next(step)
    if #M.tabs == 0 then return end
    M.select(((M.cur - 1 + (step or 1)) % #M.tabs) + 1)
  end

  -- Mostra/esconde o painel (abre a primeira aba se não houver nenhuma)
  function M.toggle()
    if valid_win() then return M.hide() end
    if #M.tabs == 0 then
      if cfg.new_button then return M.new() end
      return vim.notify("Nada rodando. Use Cmd+Shift+X para rodar um comando.", vim.log.levels.INFO, { title = cfg.title })
    end
    M.select(M.cur > 0 and M.cur or 1)
  end

  -- -------------------------------------------------------------------------
  -- Posição do painel: embaixo → direita → flutuante
  -- -------------------------------------------------------------------------
  local order = { "bottom", "right", "float" }

  function M.set(layout)
    M.layout = layout
    if valid_win() then M.hide() end
    if #M.tabs == 0 then return M.toggle() end
    M.select(M.cur > 0 and M.cur or 1)
  end

  function M.cycle()
    local idx = 1
    for i, l in ipairs(order) do if l == M.layout then idx = i end end
    M.set(order[idx % #order + 1])
  end

  local group = vim.api.nvim_create_augroup("term_panel_" .. cfg.id, { clear = true })
  -- Garante a barra de abas no painel mesmo que algum plugin troque a winbar
  vim.api.nvim_create_autocmd({ "BufWinEnter", "TermOpen" }, {
    group = group,
    callback = function() if valid_win() then style_win(M.win) end end,
  })
  -- Voltar ao painel (clique, Ctrl-w, atalho) já entra no modo de digitação,
  -- se o processo da aba ainda estiver rodando
  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      if valid_win() and vim.api.nvim_get_current_win() == M.win and M.running() then
        vim.schedule(function()
          if valid_win() and vim.api.nvim_get_current_win() == M.win and vim.bo.buftype == "terminal" then vim.cmd.startinsert() end
        end)
      end
    end,
  })
  -- Se a janela do painel for fechada por fora (:q), esquece ela (as abas continuam vivas)
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev) if M.win and tonumber(ev.match) == M.win then M.win = nil end end,
  })
  -- Se o buffer de uma aba sumir por fora, a aba sai junto
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      local i = index_of(ev.buf)
      if i then
        table.remove(M.tabs, i)
        M.cur = math.min(M.cur, #M.tabs)
        vim.schedule(redraw)
      end
    end,
  })

  return M
end
