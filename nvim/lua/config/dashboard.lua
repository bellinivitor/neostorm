-- Tela inicial (dashboard) no lugar do "[No Name]" vazio:
-- aparece ao abrir o Neovim sem sessão e quando o último arquivo é fechado.
local M = {}

local function is_empty(buf)
  return vim.api.nvim_buf_is_valid(buf)
    and vim.api.nvim_buf_get_name(buf) == ""
    and vim.bo[buf].buftype == ""
    and not vim.bo[buf].modified
    and vim.api.nvim_buf_line_count(buf) <= 1
    and (vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or "") == ""
end

local function has_real_files()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buflisted and vim.bo[b].buftype == "" and vim.api.nvim_buf_get_name(b) ~= "" then return true end
  end
  return false
end

function M.maybe_show()
  if vim.t.rollback_diff or has_real_files() then return end
  local main = require("config.panels").main_win()
  if not main then return end
  local b = vim.api.nvim_win_get_buf(main)
  if vim.bo[b].filetype == "snacks_dashboard" or not is_empty(b) then return end
  Snacks.dashboard.open({ win = main })
  -- some com os "[No Name]" vazios que sobraram
  for _, eb in ipairs(vim.api.nvim_list_bufs()) do
    if is_empty(eb) and #vim.fn.win_findbuf(eb) == 0 then pcall(vim.api.nvim_buf_delete, eb, { force = true }) end
  end
end

-- Configuração do dashboard (usada pelo snacks.nvim)
function M.config()
  local project = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
  local I = {
    file = "\u{F0214}", recent = "\u{F02DA}", search = "\u{F0349}", grep = "\u{F0BD1}",
    commit = "\u{F0718}", term = "\u{F018D}", claude = "\u{F06C4}", project = "\u{F024B}",
    lazy = "\u{F0D29}", quit = "\u{F0343}", git = "\u{F02A2}",
  }
  return {
    enabled = false, -- quem decide quando mostrar é M.maybe_show()
    width = 60,
    preset = {
      keys = {
        { icon = I.search, key = "s", desc = "Search Everywhere", action = ":FzfLua global" },
        { icon = I.file, key = "f", desc = "Abrir arquivo", action = ":FzfLua files" },
        { icon = I.recent, key = "r", desc = "Arquivos recentes", action = ":FzfLua oldfiles cwd_only=true" },
        { icon = I.grep, key = "g", desc = "Buscar no projeto", action = ":FzfLua live_grep" },
        { icon = I.commit, key = "c", desc = "Commit", action = function() require("config.commit").open() end },
        { icon = I.term, key = "t", desc = "Terminal", action = function() require("config.terminal").toggle() end },
        { icon = I.claude, key = "a", desc = "Claude Code", action = ":ClaudeCodeFocus" },
        { icon = I.project, key = "p", desc = "Trocar de projeto", action = function() Snacks.picker.projects() end },
        { icon = I.lazy, key = "l", desc = "Plugins", action = ":Lazy" },
        { icon = I.quit, key = "q", desc = "Sair", action = ":qa" },
      },
    },
    sections = {
      { text = { { project, hl = "SnacksDashboardHeader" } }, align = "center", padding = 0 },
      function()
        local branch = vim.trim(vim.fn.system({ "git", "-C", vim.fn.getcwd(), "branch", "--show-current" }))
        if vim.v.shell_error ~= 0 or branch == "" then return {} end
        return { text = { { I.git .. "  " .. branch, hl = "SnacksDashboardDesc" } }, align = "center", padding = 2 }
      end,
      { section = "keys", gap = 0, padding = 2 },
      { icon = I.recent, title = "Recentes neste projeto", section = "recent_files", cwd = true, limit = 8, indent = 2, padding = 1 },
    },
  }
end

function M.setup()
  local group = vim.api.nvim_create_augroup("dashboard_empty", { clear = true })
  -- ao abrir: espera a sessão e o painel do projeto
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    callback = function() vim.defer_fn(M.maybe_show, 120) end,
  })
  -- ao fechar o último arquivo
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function() vim.schedule(M.maybe_show) end,
  })
end

return M
