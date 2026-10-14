-- Painel do Claude Code: separado do Terminal, à direita do código, com uma linha de
-- consumo no pé da coluna:
--   ┌ Claude Code ───────────────────────────────────────────────────────────────┐
--   │ (terminal do Claude)                                                        │
--   ├─────────────────────────────────────────────────────────────────────────────┤
--   │ contexto ▰▰▱▱▱▱ 39%   sessão ▰▰▰▰▰▱ 93% 1h10   semana ▰▰▰▰▰▱ 89% 5h40        │
--   └─────────────────────────────────────────────────────────────────────────────┘
-- O resumo de consumo vem da status line do Claude aberto pelo Neovim
-- (scripts/claude-statusline.sh grava o JSON; aqui só lemos o arquivo).
require("config.terminal") -- cores dos painéis

local STATUS_FILE = vim.fn.stdpath("cache") .. "/claude-status-" .. vim.fn.getpid() .. ".json"
local SETTINGS = vim.fn.stdpath("config") .. "/claude-settings.json"

local usage = { data = nil, mtime = 0 }

-- Os limites de sessão e semana são da conta, não da conversa: guarda os últimos vistos
-- para mostrar já ao abrir o painel (o Claude só manda de novo após a primeira resposta)
local LAST_FILE = vim.fn.stdpath("cache") .. "/claude-usage-last.json"

local function read_json(path)
  local f = io.open(path, "r")
  if not f then return nil end
  -- null do JSON vira nil (e não vim.NIL), para os testes de campo vazio funcionarem
  local ok, data = pcall(vim.json.decode, f:read("*a"), { luanil = { object = true, array = true } })
  f:close()
  return ok and type(data) == "table" and data or nil
end

local function save_last(rate_limits)
  local f = io.open(LAST_FILE, "w")
  if f then f:write(vim.json.encode({ rate_limits = rate_limits, saved_at = os.time() })); f:close() end
end

local function read_usage()
  local stat = vim.uv.fs_stat(STATUS_FILE)
  if not stat or stat.mtime.sec == usage.mtime then return false end
  usage.mtime = stat.mtime.sec
  local data = read_json(STATUS_FILE)
  if not data then return false end
  usage.data = data
  if data.rate_limits and next(data.rate_limits) then save_last(data.rate_limits) end
  return true
end

-- "1h10", "5d 3h", "12min"
local function until_reset(ts)
  local s = (tonumber(ts) or 0) - os.time()
  if s <= 0 then return "" end
  local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
  if d > 0 then return d .. "d " .. h .. "h" end
  if h > 0 then return h .. "h" .. string.format("%02d", m) end
  return m .. "min"
end

-- barrinha de 6 blocos; cor pelo nível (verde, amarelo a partir de 70%, vermelho a partir de 90%)
-- level: 1 com barrinha, 2 só a porcentagem, 3 só a porcentagem e sem o tempo de reinício
local function meter(label, pct, reset, kind, level_n)
  local compact = (level_n or 1) > 1
  if type(pct) ~= "number" then return nil end
  local filled = math.max(0, math.min(6, math.floor(pct / 100 * 6 + 0.5)))
  local level = kind == "ctx" and "Ctx" or (pct >= 90 and "High" or (pct >= 70 and "Mid" or "Low"))
  local s = "%#ClaudeUsageLabel#" .. label .. " "
  if compact then
    -- sem espaço: só a porcentagem, na cor do nível
    s = s .. "%#ClaudeUsage" .. level .. "#" .. math.floor(pct + 0.5) .. "%%"
  else
    s = s .. "%#ClaudeUsage" .. level .. "#" .. string.rep("\u{25B0}", filled)
      .. "%#ClaudeUsageEmpty#" .. string.rep("\u{25B1}", 6 - filled)
      .. "%#ClaudeUsagePct# " .. math.floor(pct + 0.5) .. "%%"
  end
  if reset and reset ~= "" and (level_n or 1) < 3 then s = s .. "%#ClaudeUsageLabel# " .. reset end
  return s
end

-- "há 25min", "há 2h" (só quando o valor guardado tem mais de 10 minutos)
local function age_of(saved_at)
  local s = os.time() - (tonumber(saved_at) or os.time())
  if s < 600 then return nil end
  if s < 3600 then return "há " .. math.floor(s / 60) .. "min" end
  if s < 86400 then return "há " .. math.floor(s / 3600) .. "h" end
  return "há " .. math.floor(s / 86400) .. "d"
end

-- uma janela de limite; se o horário de reiniciar já passou, ela zerou
local function window(label, w, n)
  if not w then return nil end
  if (tonumber(w.resets_at) or 0) <= os.time() then return meter(label, 0, nil, nil, n) end
  return meter(label, w.used_percentage, until_reset(w.resets_at), nil, n)
end

local panel -- o painel (definido mais abaixo), para saber a largura disponível

local function build(d, rl, age, n)
  local parts = {}
  -- contexto: conversa nova (ainda sem resposta) conta como 0%
  local cw = d.context_window
  local ctx = cw and (cw.used_percentage or ((cw.total_input_tokens or 0) == 0 and 0 or nil))
  table.insert(parts, meter("contexto", ctx, nil, "ctx", n))
  table.insert(parts, window("sessão", rl.five_hour, n))
  table.insert(parts, window("semana", rl.seven_day, n))
  parts = vim.tbl_filter(function(x) return x ~= nil end, parts)
  if #parts == 0 then return nil end
  -- valores guardados de antes: uma indicação só, no fim
  -- (no nível mais enxuto fica de fora, para caber)
  local tail = (age and n < 3) and ("%#ClaudeUsageLabel#  (" .. age .. ")") or ""
  return table.concat(parts, "%#ClaudeUsageLabel#" .. (n > 1 and "  " or "   ")) .. tail .. " "
end

local function summary(room)
  local d = usage.data or {}
  -- limites: os desta sessão ou, antes da primeira resposta, os últimos guardados
  local rl, age = d.rate_limits, nil
  if not (rl and next(rl)) then
    local last = read_json(LAST_FILE)
    rl = last and last.rate_limits
    age = last and age_of(last.saved_at)
  end
  rl = rl or {}
  local function fits(str)
    local plain = str:gsub("%%#[^#]*#", ""):gsub("%%%%", "%%")
    return vim.fn.strdisplaywidth(plain) <= room
  end
  -- do mais completo ao mais enxuto, o primeiro que couber
  local last
  for n = 1, 3 do
    last = build(d, rl, age, n)
    if not last then return "%#ClaudeUsageLabel#o consumo aparece após a primeira resposta " end
    if fits(last) then return last end
  end
  return last
end

local M = require("config.term_panel")({
  id = "claude",
  title = "Claude Code",
  module = "config.claude_panel",
  layout = "right",
  hide_tabs = true,
  tab_icon = function() return "\u{2733}", "TermTabClaude" end,
})

panel = M
M.status_file = STATUS_FILE

-- ---------------------------------------------------------------------------
-- Rodapé de uma linha com o consumo
-- Criado sem trocar de janela (nvim_open_win com enter = false): trocar de janela tirava
-- o terminal do Claude do modo de digitação.
-- ---------------------------------------------------------------------------
local ns = vim.api.nvim_create_namespace("claude_usage_line")
local foot = { buf = nil, win = nil }

local function foot_valid() return foot.win and vim.api.nvim_win_is_valid(foot.win) end

-- converte o texto no formato da statusline ("%#Grupo#texto", "%%") em texto + cores
local function to_line(str)
  local text, marks, hl = "", {}, "ClaudeUsageLabel"
  local i = 1
  while i <= #str do
    local g, e = str:match("^%%#([^#]*)#()", i)
    if g then
      hl, i = g, e
    else
      local chunk = str:match("^[^%%]+", i) or (str:sub(i, i + 1) == "%%" and "%" or str:sub(i, i))
      local step = (str:sub(i, i + 1) == "%%") and 2 or #chunk
      table.insert(marks, { #text, #text + #chunk, hl })
      text = text .. chunk
      i = i + step
    end
  end
  return text, marks
end

local function render_footer()
  if not foot_valid() then return end
  local width = vim.api.nvim_win_get_width(foot.win)
  local text, marks = to_line(" " .. summary(width - 2))
  vim.bo[foot.buf].modifiable = true
  vim.api.nvim_buf_set_lines(foot.buf, 0, -1, false, { text })
  vim.bo[foot.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(foot.buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    if m[1] < m[2] then vim.api.nvim_buf_set_extmark(foot.buf, ns, 0, m[1], { end_col = m[2], hl_group = m[3] }) end
  end
end

local function close_footer()
  if foot_valid() then pcall(vim.api.nvim_win_close, foot.win, true) end
  foot.win = nil
end

local function ensure_footer()
  if not (M.is_open() and M.layout == "right") then return close_footer() end
  if foot_valid() then return end
  if not (foot.buf and vim.api.nvim_buf_is_valid(foot.buf)) then
    foot.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[foot.buf].bufhidden = "hide"
    vim.bo[foot.buf].filetype = "claude_usage"
  end
  foot.win = vim.api.nvim_open_win(foot.buf, false, { split = "below", win = M.win, height = 1 })
  local wo = vim.wo[foot.win]
  wo.number, wo.relativenumber, wo.signcolumn, wo.statuscolumn = false, false, "no", ""
  wo.foldcolumn, wo.cursorline, wo.wrap, wo.winbar = "0", false, false, ""
  wo.winfixheight = true
  -- o Neovim redistribui as alturas ao criar a janela: trava em 1 linha depois
  vim.api.nvim_win_set_height(foot.win, 1)
  wo.winhighlight = "Normal:ClaudeUsageLine,NormalNC:ClaudeUsageLine,EndOfBuffer:ClaudeUsageLine"
  require("config.panels").mark(foot.win, foot.buf)
  render_footer()
end
M.ensure_footer = ensure_footer

-- o rodapé acompanha o painel: esconder o painel esconde o rodapé
local hide = M.hide
function M.hide()
  close_footer()
  hide()
end

vim.api.nvim_create_autocmd("WinClosed", {
  callback = function(ev)
    if M.win and tonumber(ev.match) == M.win then vim.schedule(close_footer) end
  end,
})
-- o rodapé nunca fica com o foco (clique nele volta para o Claude)
vim.api.nvim_create_autocmd("WinEnter", {
  callback = function()
    if foot_valid() and vim.api.nvim_get_current_win() == foot.win then
      vim.schedule(function() if M.win and vim.api.nvim_win_is_valid(M.win) then vim.api.nvim_set_current_win(M.win) end end)
    end
  end,
})
vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
  callback = function()
    if not foot_valid() then return end
    if vim.api.nvim_win_get_height(foot.win) ~= 1 then pcall(vim.api.nvim_win_set_height, foot.win, 1) end
    render_footer()
  end,
})

-- A cada 2s: garante o rodapé e atualiza se o consumo mudou
local timer = vim.uv.new_timer()
timer:start(2000, 2000, vim.schedule_wrap(function()
  if not M.is_open() then return close_footer() end
  ensure_footer()
  if read_usage() then render_footer() end
end))
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function() pcall(os.remove, STATUS_FILE) end,
})

-- ---------------------------------------------------------------------------
-- Provedor de terminal para o claudecode.nvim: o Claude Code abre neste painel
-- ---------------------------------------------------------------------------
local function with_status(env)
  env = vim.deepcopy(env or {})
  env.NVIM_CLAUDE_STATUS = STATUS_FILE
  return env
end

local function index() return M.tabs[1] and 1 or nil end

M.provider = {
  setup = function() end,
  is_available = function() return true end,
  open = function(cmd, env, _, focus)
    local i = index()
    if i then M.select(i, focus) else
      M.new({ name = "Claude Code", cmd = cmd, env = with_status(env), claude = true, focus = focus })
    end
    ensure_footer()
  end,
  close = function()
    local i = index()
    if i then M.close(i) end
  end,
  simple_toggle = function(cmd, env)
    if M.is_open() then return M.hide() end
    M.provider.open(cmd, env, nil, true)
  end,
  focus_toggle = function(cmd, env)
    if M.is_open() and vim.api.nvim_get_current_win() == M.win then return M.hide() end
    M.provider.open(cmd, env, nil, true)
  end,
  get_active_bufnr = function()
    local i = index()
    return i and M.tabs[i].buf or nil
  end,
}

-- comando do Claude com a status line que grava o consumo para o painel
M.cmd = "claude --settings " .. vim.fn.shellescape(SETTINGS)

local function colors()
  local ok, c = pcall(require, "config.palette")
  if not ok then return end
  local set = vim.api.nvim_set_hl
  set(0, "ClaudeUsageLabel", { fg = c.fg_dim, bg = c.bg })
  set(0, "ClaudeUsagePct", { fg = c.fg, bg = c.bg })
  set(0, "ClaudeUsageEmpty", { fg = c.linenr, bg = c.bg })
  set(0, "ClaudeUsageCtx", { fg = c.info, bg = c.bg })
  set(0, "ClaudeUsageLow", { fg = c.hint, bg = c.bg })
  set(0, "ClaudeUsageMid", { fg = c.warn, bg = c.bg })
  set(0, "ClaudeUsageHigh", { fg = c.error, bg = c.bg })
  set(0, "ClaudeUsageLine", { fg = c.fg_dim, bg = c.bg })
end
colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = colors })

return M
