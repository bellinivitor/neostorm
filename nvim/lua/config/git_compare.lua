-- Compare de branches, no estilo da janela do PhpStorm:
--   ┌ ⚠ Commits que existem em A mas não em B (n) ┐┌ detalhes do commit ┐
--   │ autor        data            ●  título   ref ││ título, autor, data │
--   ├ ⚠ Commits que existem em B mas não em A (n) ┤│ arquivos alterados  │
--   │ ...                                          ││ (Enter abre o diff) │
--   └──────────────────────────────────────────────┘└─────────────────────┘
-- q fecha, Tab alterna entre as listas e os detalhes.
local M = {}

local ns = vim.api.nvim_create_namespace("git_compare")
local AUTHOR_W, DATE_W = 18, 15
local I = { warn = "\u{F0026}", dot = "\u{25CF}", merge = "\u{2022}", ref = "\u{F04F9}" }

local function git(root, args)
  local cmd = { "git" }
  vim.list_extend(cmd, args)
  local r = vim.system(cmd, { cwd = root, text = true }):wait()
  return r.code == 0 and r.stdout or "", r
end

local function trunc(s, w)
  if w <= 0 then return "" end
  if vim.fn.strdisplaywidth(s) <= w then return s end
  return vim.fn.strcharpart(s, 0, math.max(0, w - 1)) .. "…"
end

local function pad(s, w) return s .. string.rep(" ", math.max(0, w - vim.fn.strdisplaywidth(s))) end

-- Branches e tags do commit, sem o "HEAD ->" e com no máximo duas
local function short_refs(d)
  if d == "" then return "" end
  local refs = {}
  for r in d:gmatch("[^,]+") do
    r = vim.trim(r):gsub("^HEAD %-> ", ""):gsub("^tag: ", "")
    if r ~= "HEAD" and r ~= "" then table.insert(refs, r) end
  end
  if #refs == 0 then return "" end
  return I.ref .. " " .. table.concat(refs, ", ", 1, math.min(2, #refs)) .. (#refs > 2 and " +" .. (#refs - 2) or "")
end

local function load_commits(root, range)
  local out = git(root, { "log", "--date=format:%d/%m/%y, %H:%M",
    "--format=%H%x1f%an%x1f%ad%x1f%s%x1f%P%x1f%D", range })
  local list = {}
  for line in out:gmatch("[^\n]+") do
    local h, an, ad, s, p, d = line:match("^(.-)\31(.-)\31(.-)\31(.-)\31(.-)\31(.*)$")
    if h then
      local parents = vim.split(p, " ", { trimempty = true })
      table.insert(list, { hash = h, author = an, date = ad, subject = s, merge = #parents > 1, refs = short_refs(d) })
    end
  end
  return list
end

-- ---------------------------------------------------------------------------
-- Lista de commits (uma por sentido)
-- ---------------------------------------------------------------------------
local function render_list(view, side)
  local L = view.lists[side]
  if not (L.win and vim.api.nvim_win_is_valid(L.win)) then return end
  local width = vim.api.nvim_win_get_width(L.win)
  local text, marks = {}, {}
  if #L.commits == 0 then
    text = { "", pad("", math.floor((width - 16) / 2)) .. "Nenhum commit" }
    table.insert(marks, { 1, 0, -1, "CompareEmpty" })
  end
  for i, c in ipairs(L.commits) do
    local mine = c.author == view.me
    local author = pad(trunc(c.author, AUTHOR_W), AUTHOR_W)
    local date = pad(c.date, DATE_W)
    local dot = c.merge and I.merge or I.dot
    local left = " " .. author .. "  " .. date .. "  " .. dot .. "  "
    local refs = c.refs ~= "" and trunc(c.refs, math.floor(width * 0.3)) or ""
    local room = width - vim.fn.strdisplaywidth(left) - (refs ~= "" and vim.fn.strdisplaywidth(refs) + 3 or 1)
    local subject = trunc(c.subject, room)
    local line = left .. subject
    if refs ~= "" then line = pad(line, width - vim.fn.strdisplaywidth(refs) - 1) .. refs end
    table.insert(text, line)
    local r = i - 1
    local a0 = 1
    local d0 = a0 + #author + 2
    local p0 = d0 + #date + 2
    local s0 = p0 + #dot + 2
    table.insert(marks, { r, a0, a0 + #author, c.merge and "CompareMerge" or (mine and "CompareAuthorMe" or "CompareAuthor") })
    table.insert(marks, { r, d0, d0 + #date, c.merge and "CompareMerge" or "CompareDate" })
    table.insert(marks, { r, p0, p0 + #dot, c.merge and "CompareDotMerge" or "CompareDot" })
    table.insert(marks, { r, s0, s0 + #subject, c.merge and "CompareMerge" or "CompareSubject" })
    if refs ~= "" then table.insert(marks, { r, #line - #refs, #line, "CompareRef" }) end
  end
  local buf = L.buf
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    local len = #text[m[1] + 1]
    local e = m[3] == -1 and len or math.min(m[3], len)
    if m[2] < e then vim.api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = e, hl_group = m[4] }) end
  end
end

local function header(view, side)
  local L = view.lists[side]
  local function esc(s) return (s:gsub("%%", "%%%%")) end
  return "%#CompareHeaderIcon# " .. I.warn .. " %#CompareHeader#Commits que existem em %#CompareHeaderBranch#"
    .. esc(L.has) .. "%#CompareHeader# mas não em %#CompareHeaderBranch#" .. esc(L.lacks)
    .. "%#CompareHeader#  (" .. #L.commits .. ")%="
end

-- ---------------------------------------------------------------------------
-- Detalhes do commit (painel da direita)
-- ---------------------------------------------------------------------------
local STATUS_HL = { M = "CompareFileM", A = "CompareFileA", D = "CompareFileD", R = "CompareFileR", C = "CompareFileR" }

local function render_details(view, commit)
  local buf, win = view.details.buf, view.details.win
  if not (win and vim.api.nvim_win_is_valid(win)) then return end
  local text, marks = {}, {}
  view.details.files = {}
  if not commit then
    local width = vim.api.nvim_win_get_width(win)
    text = { "", "", pad("", math.floor((width - 40) / 2)) .. "Selecione um commit para ver as alterações" }
    table.insert(marks, { 2, 0, -1, "CompareEmpty" })
  else
    local body = git(view.root, { "show", "-s", "--format=%B", commit.hash })
    local msg = vim.split(vim.trim(body), "\n", { plain = true })
    for i, l in ipairs(msg) do
      table.insert(text, " " .. l)
      if i == 1 then table.insert(marks, { #text - 1, 0, -1, "CompareTitle" }) end
    end
    table.insert(text, "")
    table.insert(text, " " .. commit.hash:sub(1, 8) .. "  " .. commit.author .. "  " .. commit.date)
    table.insert(marks, { #text - 1, 0, -1, "CompareMeta" })
    local parent = commit.hash .. "^"
    local files = git(view.root, { "diff", "--name-status", "-M", parent, commit.hash })
    local list = {}
    for line in files:gmatch("[^\n]+") do
      local parts = vim.split(line, "\t", { plain = true })
      local st = parts[1]:sub(1, 1)
      table.insert(list, { status = st, path = parts[3] or parts[2], old = parts[2] })
    end
    table.insert(text, "")
    table.insert(text, " Arquivos alterados (" .. #list .. ")")
    table.insert(marks, { #text - 1, 0, -1, "CompareSection" })
    for _, f in ipairs(list) do
      local shown = f.status == "R" and (f.old .. " → " .. f.path) or f.path
      table.insert(text, "   " .. f.status .. "  " .. shown)
      view.details.files[#text] = { commit = commit.hash, status = f.status, path = f.path, old = f.old }
      table.insert(marks, { #text - 1, 3, 4, STATUS_HL[f.status] or "CompareMeta" })
      table.insert(marks, { #text - 1, 6, -1, "CompareSubject" })
    end
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    local len = #text[m[1] + 1]
    local e = m[3] == -1 and len or math.min(m[3], len)
    if m[2] < e then vim.api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = e, hl_group = m[4] }) end
  end
end

-- Diff lado a lado de um arquivo do commit (antes ↔ depois), numa aba nova
local function file_diff(view, f)
  local short = f.commit:sub(1, 8)
  local before = f.status == "A" and "" or git(view.root, { "show", f.commit .. "^:" .. f.old })
  local after = f.status == "D" and "" or git(view.root, { "show", f.commit .. ":" .. f.path })
  local ft = vim.filetype.match({ filename = f.path }) or ""
  vim.cmd("tabnew")
  vim.t.no_activity_bar = true
  local function side(content, label)
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n", { plain = true }))
    vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].modifiable = "nofile", "wipe", false
    vim.bo[buf].filetype = ft
    vim.wo.winbar = "%#CompareMeta# " .. label .. " %*"
    vim.cmd("diffthis")
    vim.keymap.set("n", "q", "<cmd>tabclose<cr>", { buffer = buf, desc = "Fechar" })
  end
  side(before, "Antes (" .. short .. "^)  " .. f.old)
  vim.cmd("rightbelow vnew")
  side(after, "Depois (" .. short .. ")  " .. f.path)
  M.own_tab()
end

-- ---------------------------------------------------------------------------
-- Telas em aba própria (Compare, diff, janela de Git): fecham inteiras
-- A barra de abas mostra arquivos, não abas do Neovim; então q, Cmd+W, :q ou fechar uma
-- coluna fecham a aba toda (antes o Cmd+W fechava uma coluna por vez e sobrava lixo).
-- ---------------------------------------------------------------------------
function M.own_tab(tab)
  tab = tab or vim.api.nvim_get_current_tabpage()
  local closing = false
  local function close_tab()
    if closing or not vim.api.nvim_tabpage_is_valid(tab) then return end
    closing = true
    if #vim.api.nvim_list_tabpages() > 1 then
      pcall(vim.api.nvim_set_current_tabpage, tab)
      pcall(vim.cmd, "tabclose")
    else
      -- era a única aba: limpa as janelas e volta para um buffer vazio
      pcall(vim.cmd, "silent! only | enew")
    end
  end
  local wins = {}
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    wins[w] = true
    local b = vim.api.nvim_win_get_buf(w)
    for _, lhs in ipairs({ "q", "<D-w>" }) do
      vim.keymap.set("n", lhs, close_tab, { buffer = b, nowait = true, desc = "Fechar a tela" })
    end
  end
  local group = vim.api.nvim_create_augroup("own_tab_" .. tab, { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      if not vim.api.nvim_tabpage_is_valid(tab) then pcall(vim.api.nvim_del_augroup_by_id, group); return end
      if wins[tonumber(ev.match)] then vim.schedule(close_tab) end
    end,
  })
  M.close_tab = close_tab
  return close_tab
end

--- Diff lado a lado de um arquivo de um commit (usado também pela janela de Git)
--- f = { commit, status, path, old }
function M.file_diff(root, f) file_diff({ root = root }, f) end

-- ---------------------------------------------------------------------------
-- Abrir
-- ---------------------------------------------------------------------------
local function style(win, opts)
  local wo = vim.wo[win]
  wo.number, wo.relativenumber, wo.signcolumn, wo.statuscolumn = false, false, "no", ""
  wo.foldcolumn, wo.foldenable, wo.list, wo.spell = "0", false, false, false
  wo.wrap = opts.wrap or false
  wo.linebreak = opts.wrap or false
  wo.cursorline = opts.cursorline or false
  wo.winhighlight = "Normal:ComparePanel,NormalNC:ComparePanel,CursorLine:CompareSel,WinBar:CompareHeader,WinBarNC:CompareHeader,EndOfBuffer:ComparePanel"
end

local function scratch(name)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "git_compare"
  pcall(vim.api.nvim_buf_set_name, buf, name)
  return buf
end

--- Compara duas branches: other (a escolhida no popup) e cur (a atual)
function M.open(root, other, cur)
  local view = {
    root = root,
    me = vim.trim(git(root, { "config", "user.name" })),
    lists = {
      { has = other, lacks = cur, commits = load_commits(root, cur .. ".." .. other) },
      { has = cur, lacks = other, commits = load_commits(root, other .. ".." .. cur) },
    },
    details = {},
  }

  vim.cmd("tabnew")
  vim.t.no_activity_bar = true
  local top = vim.api.nvim_get_current_win()
  local placeholder = vim.api.nvim_get_current_buf()
  -- detalhes à direita (40%), as duas listas empilhadas à esquerda
  view.details.buf = scratch("Compare: detalhes")
  vim.cmd("botright vsplit")
  view.details.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(view.details.win, view.details.buf)
  vim.api.nvim_win_set_width(view.details.win, math.floor(vim.o.columns * 0.38))
  style(view.details.win, { wrap = true, cursorline = true })
  vim.wo[view.details.win].winbar = "%#CompareDetailsBar#"

  vim.api.nvim_set_current_win(top)
  vim.cmd("belowright split")
  local bottom = vim.api.nvim_get_current_win()
  for side, win in ipairs({ top, bottom }) do
    local L = view.lists[side]
    L.win = win
    L.buf = scratch("Compare: " .. L.has .. " ↔ " .. L.lacks)
    vim.api.nvim_win_set_buf(win, L.buf)
    style(win, { cursorline = true })
    vim.wo[win].winbar = header(view, side)
  end
  if vim.api.nvim_buf_is_valid(placeholder) then pcall(vim.api.nvim_buf_delete, placeholder, { force = true }) end
  -- lista vazia fica baixinha e a outra ganha o espaço; com as duas cheias, metade cada
  local total = vim.api.nvim_win_get_height(top) + vim.api.nvim_win_get_height(bottom)
  local n1, n2 = #view.lists[1].commits, #view.lists[2].commits
  local h1 = (n1 == 0 and 4) or (n2 == 0 and total - 4) or math.floor(total / 2)
  vim.api.nvim_win_set_height(top, h1)

  local function current_commit()
    for _, L in ipairs(view.lists) do
      if vim.api.nvim_get_current_win() == L.win then
        return L.commits[vim.api.nvim_win_get_cursor(L.win)[1]]
      end
    end
  end

  for side, L in ipairs(view.lists) do
    render_list(view, side)
    local function map(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = L.buf, nowait = true }) end
    map("q", "<cmd>tabclose<cr>")
    map("<CR>", function() vim.api.nvim_set_current_win(view.details.win) end)
    map("<Tab>", function()
      vim.api.nvim_set_current_win(side == 1 and view.lists[2].win or view.details.win)
    end)
    vim.api.nvim_create_autocmd("CursorMoved", {
      buffer = L.buf,
      callback = function() render_details(view, current_commit()) end,
    })
    vim.api.nvim_create_autocmd("WinEnter", {
      buffer = L.buf,
      callback = function() render_details(view, current_commit()) end,
    })
  end
  local dbuf = view.details.buf
  vim.keymap.set("n", "q", "<cmd>tabclose<cr>", { buffer = dbuf, nowait = true })
  vim.keymap.set("n", "<Tab>", function() vim.api.nvim_set_current_win(view.lists[1].win) end, { buffer = dbuf, nowait = true })
  local function open_file()
    local f = view.details.files[vim.api.nvim_win_get_cursor(0)[1]]
    if f then file_diff(view, f) end
  end
  vim.keymap.set("n", "<CR>", open_file, { buffer = dbuf, nowait = true })
  vim.keymap.set("n", "<2-LeftMouse>", require("config.panels").after_click(open_file), { buffer = dbuf, nowait = true })

  vim.api.nvim_create_autocmd("WinResized", {
    callback = function()
      if not vim.api.nvim_buf_is_valid(view.lists[1].buf) then return true end
      for side in ipairs(view.lists) do render_list(view, side) end
    end,
  })

  -- começa na lista que tem commits
  local start = #view.lists[1].commits > 0 and 1 or 2
  vim.api.nvim_set_current_win(view.lists[start].win)
  render_details(view, view.lists[start].commits[1])
  M.own_tab()
end

-- ---------------------------------------------------------------------------
-- Diff de uma branch com os seus arquivos (Show Diff with Working Tree):
--   ┌ lista de arquivos alterados ┐┌ na branch ──────┬ seus arquivos ───┐
--   │ M  Arquivo.php   pasta  +8 −1 ││ (lado a lado, muda conforme a lista) │
-- ---------------------------------------------------------------------------
local function changed_files(root, ref)
  local status = {}
  for line in git(root, { "diff", "--name-status", "-M", ref }):gmatch("[^\n]+") do
    local p = vim.split(line, "\t", { plain = true })
    status[p[3] or p[2]] = { status = p[1]:sub(1, 1), old = p[2] }
  end
  local files = {}
  for line in git(root, { "diff", "--numstat", "-M", ref }):gmatch("[^\n]+") do
    local add, del, path = line:match("^(%S+)\t(%S+)\t(.+)$")
    if path then
      -- renomeado aparece como "pasta/{antigo => novo}.php" no numstat
      local new = path:gsub("{.- => (.-)}", "%1"):gsub("//", "/")
      local st = status[new] or { status = "M", old = new }
      table.insert(files, { path = new, old = st.old, status = st.status, add = tonumber(add) or 0, del = tonumber(del) or 0 })
    end
  end
  table.sort(files, function(a, b) return a.path < b.path end)
  return files
end

local function set_side(buf, lines, path)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  -- só a cor de sintaxe (sem disparar o FileType, que mexeria nas dobras da janela)
  local ft = vim.filetype.match({ filename = path }) or ""
  local lang = ft ~= "" and vim.treesitter.language.get_lang(ft) or nil
  pcall(vim.treesitter.stop, buf)
  if lang then pcall(vim.treesitter.start, buf, lang) end
end

function M.working_tree(root, ref)
  local files = changed_files(root, ref)
  local adds, dels = 0, 0
  for _, f in ipairs(files) do adds, dels = adds + f.add, dels + f.del end

  vim.cmd("tabnew")
  vim.t.no_activity_bar = true
  local list_win = vim.api.nvim_get_current_win()
  local placeholder = vim.api.nvim_get_current_buf()
  local list_buf = scratch("Diff: " .. ref .. " ↔ seus arquivos")
  vim.api.nvim_win_set_buf(list_win, list_buf)
  if vim.api.nvim_buf_is_valid(placeholder) and placeholder ~= list_buf then pcall(vim.api.nvim_buf_delete, placeholder, { force = true }) end
  style(list_win, { cursorline = true })
  local function esc(x) return (x:gsub("%%", "%%%%")) end
  vim.wo[list_win].winbar = "%#CompareBar# " .. #files .. " arquivo" .. (#files == 1 and "" or "s") .. " diferente"
    .. (#files == 1 and "" or "s") .. " de %#CompareBarStrong#" .. esc(ref) .. "%#CompareBar#  %#CompareBarAdd#+" .. adds
    .. " %#CompareBarDel#−" .. dels .. "%#CompareBar#%="

  -- dois lados do diff à direita
  local left_buf, right_buf = scratch("Na branch"), scratch("Seus arquivos")
  vim.cmd("rightbelow vsplit")
  local left_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(left_win, left_buf)
  vim.cmd("rightbelow vsplit")
  local right_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(right_win, right_buf)
  vim.api.nvim_win_set_width(list_win, math.max(40, math.floor(vim.o.columns * 0.3)))
  for _, w in ipairs({ left_win, right_win }) do
    local wo = vim.wo[w]
    wo.number, wo.relativenumber, wo.signcolumn, wo.statuscolumn, wo.foldcolumn = true, false, "no", "", "0"
    wo.winhighlight = "WinBar:CompareBar,WinBarNC:CompareBar"
  end
  vim.api.nvim_win_call(left_win, function() vim.cmd("diffthis") end)
  vim.api.nvim_win_call(right_win, function() vim.cmd("diffthis") end)

  -- lista
  local function render()
    local width = vim.api.nvim_win_get_width(list_win)
    local text, marks = {}, {}
    if #files == 0 then
      text = { "", "  Nenhuma diferença: seus arquivos", "  estão iguais a " .. ref .. "." }
      table.insert(marks, { 1, 0, -1, "CompareEmpty" }); table.insert(marks, { 2, 0, -1, "CompareEmpty" })
    end
    for i, f in ipairs(files) do
      local name = vim.fn.fnamemodify(f.path, ":t")
      local dir = vim.fn.fnamemodify(f.path, ":h")
      dir = dir == "." and "" or dir
      local counts = "+" .. f.add .. " −" .. f.del
      local left = "  " .. f.status .. "  " .. name .. "  "
      local room = width - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(counts) - 3
      -- pasta encurtada pela esquerda (o fim do caminho é o que importa)
      if vim.fn.strdisplaywidth(dir) > room then
        dir = room > 2 and ("…" .. vim.fn.strcharpart(dir, vim.fn.strchars(dir) - room + 1)) or ""
      end
      local line = pad(left .. dir, width - vim.fn.strdisplaywidth(counts) - 1) .. counts
      table.insert(text, line)
      local r = i - 1
      table.insert(marks, { r, 2, 3, STATUS_HL[f.status] or "CompareMeta" })
      table.insert(marks, { r, 5, 5 + #name, "CompareSubject" })
      table.insert(marks, { r, #left, #left + #dir, "CompareRef" })
      local c0 = #line - #counts
      local plus = "+" .. f.add
      table.insert(marks, { r, c0, c0 + #plus, "CompareBarAdd" })
      table.insert(marks, { r, c0 + #plus + 1, #line, "CompareBarDel" })
    end
    vim.bo[list_buf].modifiable = true
    vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, text)
    vim.bo[list_buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(list_buf, ns, 0, -1)
    for _, m in ipairs(marks) do
      local len = #text[m[1] + 1]
      local e = m[3] == -1 and len or math.min(m[3], len)
      if m[2] < e then vim.api.nvim_buf_set_extmark(list_buf, ns, m[1], m[2], { end_col = e, hl_group = m[4] }) end
    end
  end

  local shown
  local function show(i)
    local f = files[i]
    if not f or shown == f then return end
    shown = f
    local before = f.status == "A" and {} or vim.split(git(root, { "show", ref .. ":" .. f.old }), "\n", { plain = true })
    local after = {}
    if f.status ~= "D" then
      local ok, l = pcall(vim.fn.readfile, root .. "/" .. f.path)
      after = ok and l or {}
    end
    if before[#before] == "" then table.remove(before) end
    set_side(left_buf, before, f.old)
    set_side(right_buf, after, f.path)
    -- rótulo primeiro e só o nome do arquivo (a pasta está na lista); se faltar espaço, corta o fim
    local function tail(x) return esc(vim.fn.fnamemodify(x, ":t")) end
    vim.wo[left_win].winbar = "%#CompareBarStrong# " .. esc(ref) .. "%#CompareBar#  %<" .. tail(f.status == "R" and f.old or f.path)
      .. (f.status == "A" and "  (não existe nesta branch)" or "")
    vim.wo[right_win].winbar = "%#CompareBarStrong# Seus arquivos%#CompareBar#  %<" .. tail(f.path) .. (f.status == "D" and "  (apagado)" or "")
    for _, w in ipairs({ left_win, right_win }) do
      vim.api.nvim_win_call(w, function() vim.cmd("diffupdate"); pcall(vim.cmd, "normal! gg]c") end)
    end
  end

  render()
  show(1)

  local function map(lhs, fn, buf) vim.keymap.set("n", lhs, fn, { buffer = buf or list_buf, nowait = true }) end
  for _, b in ipairs({ list_buf, left_buf, right_buf }) do
    map("q", "<cmd>tabclose<cr>", b)
    -- o abre o arquivo de verdade no editor (para editar)
    map("o", function()
      local f = shown
      if not f or f.status == "D" then return end
      vim.cmd("tabclose")
      vim.cmd.edit(vim.fn.fnameescape(root .. "/" .. f.path))
    end, b)
  end
  map("<CR>", function() vim.api.nvim_set_current_win(right_win) end)
  map("<Tab>", function() vim.api.nvim_set_current_win(right_win) end)
  map("<Tab>", function() vim.api.nvim_set_current_win(list_win) end, right_buf)
  map("<Tab>", function() vim.api.nvim_set_current_win(list_win) end, left_buf)
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = list_buf,
    callback = function() show(vim.api.nvim_win_get_cursor(list_win)[1]) end,
  })
  vim.api.nvim_create_autocmd("WinResized", {
    callback = function()
      if not vim.api.nvim_buf_is_valid(list_buf) then return true end
      if vim.api.nvim_win_is_valid(list_win) then render() end
    end,
  })
  vim.api.nvim_set_current_win(list_win)
  M.own_tab()
end

local function colors()
  local ok, c = pcall(require, "config.palette")
  if not ok then return end
  local set = vim.api.nvim_set_hl
  -- a faixa âmbar de aviso do PhpStorm
  local amber = "#4A3D1F"
  set(0, "ComparePanel", { fg = c.fg, bg = c.bg })
  set(0, "CompareHeader", { fg = "#DFE1E5", bg = amber })
  set(0, "CompareHeaderBranch", { fg = "#FFFFFF", bg = amber, bold = true })
  set(0, "CompareHeaderIcon", { fg = c.warn, bg = amber })
  set(0, "CompareDetailsBar", { bg = c.bg })
  set(0, "CompareSel", { bg = "#2E436E" })
  set(0, "CompareAuthor", { fg = c.fg })
  set(0, "CompareAuthorMe", { fg = "#DFE1E5", bold = true })
  set(0, "CompareDate", { fg = c.fg_dim })
  set(0, "CompareDot", { fg = c.variable })
  set(0, "CompareDotMerge", { fg = c.fg_faint })
  set(0, "CompareSubject", { fg = c.fg })
  set(0, "CompareMerge", { fg = c.fg_faint })
  set(0, "CompareRef", { fg = c.fg_faint })
  set(0, "CompareEmpty", { fg = c.fg_faint })
  set(0, "CompareTitle", { fg = "#DFE1E5", bold = true })
  set(0, "CompareMeta", { fg = c.fg_dim })
  set(0, "CompareSection", { fg = c.fg_dim, bold = true })
  set(0, "CompareFileM", { fg = c.change })
  set(0, "CompareFileA", { fg = c.add })
  set(0, "CompareFileD", { fg = c.error })
  set(0, "CompareFileR", { fg = c.warn })
  -- barras do diff com os seus arquivos (neutras; o âmbar fica só para o aviso do Compare)
  set(0, "CompareBar", { fg = c.fg_dim, bg = c.bg_alt })
  set(0, "CompareBarStrong", { fg = "#DFE1E5", bg = c.bg_alt, bold = true })
  set(0, "CompareBarAdd", { fg = c.add, bg = c.bg_alt })
  set(0, "CompareBarDel", { fg = c.error, bg = c.bg_alt })
end
colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = colors })

return M
