-- Menuzinho flutuante no estilo PhpStorm (usado na barra do git e no painel de alterações)
-- items = { { label = "...", key = "d", hint = "⌥⌘Z", run = function() end }, ... }
local M = {}

local menu_win

function M.close()
  if menu_win and vim.api.nvim_win_is_valid(menu_win) then vim.api.nvim_win_close(menu_win, true) end
  menu_win = nil
end

function M.open(items, opts)
  opts = opts or {}
  M.close()

  local width = opts.width or 24
  local lines = {}
  for _, it in ipairs(items) do
    local right = (it.hint and (it.hint .. "  ") or "") .. (it.key or "")
    local pad = width - vim.fn.strdisplaywidth(it.label) - vim.fn.strdisplaywidth(right) - 1
    table.insert(lines, " " .. it.label .. string.rep(" ", math.max(pad, 1)) .. right)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "popup_menu"

  menu_win = vim.api.nvim_open_win(buf, true, {
    relative = opts.mouse and "mouse" or "cursor",
    row = 1, col = opts.mouse and 1 or 0,
    width = width, height = #lines,
    style = "minimal", border = "rounded", zindex = 200,
    title = opts.title and (" " .. opts.title .. " ") or nil,
  })
  vim.wo[menu_win].cursorline = true
  vim.wo[menu_win].winhighlight = "Normal:NormalFloat,CursorLine:PmenuSel,FloatTitle:Title"
  local this_menu = menu_win

  local function run(i)
    M.close()
    if items[i] then vim.schedule(items[i].run) end
  end
  local function map(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true }) end
  map("<CR>", function() run(vim.api.nvim_win_get_cursor(0)[1]) end)
  for i, it in ipairs(items) do
    if it.key then map(it.key, function() run(i) end) end
  end
  map("<Esc>", M.close)
  map("q", M.close)
  -- Clique num item. O "soltar" do clique que abriu o menu cai fora dele e é ignorado;
  -- clicar fora fecha pelo WinLeave.
  map("<LeftRelease>", function()
    local pos = vim.fn.getmousepos()
    if pos.winid == this_menu then run(pos.line) end
  end)
  map("<RightRelease>", "<Nop>")
  vim.api.nvim_create_autocmd("WinLeave", { buffer = buf, once = true, callback = M.close })
end

return M
