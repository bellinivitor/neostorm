-- Janela de Git no estilo do Log do PhpStorm (no lugar do lazygit):
--   ┌ branches ─────┐┌ log ──────────────────────────────────┐┌ arquivos do commit ┐
--   │ Todas         ││ autor   data   ●╮  título       refs  ││ 📁 app/…  2       │
--   │ HEAD          ││ autor   data   │●  título             ││    M  Arquivo.php  │
--   │ ▾ Local       ││ …                                     │├ detalhes ─────────┤
--   │   ★ dev       ││                                       ││ mensagem, autor…   │
--   └───────────────┘└───────────────────────────────────────┘└────────────────────┘
-- Enter: na árvore escolhe a branch (ou abre/fecha a pasta); no log vai para os arquivos;
-- num arquivo abre o diff. / busca por texto ou hash. r recarrega. Tab troca de painel. q fecha.
local M = {}

local ns = vim.api.nvim_create_namespace("git_log")
local AUTHOR_W, DATE_W, GRAPH_MAX = 18, 15, 16
local FAVORITES = { main = true, master = true, develop = true, dev = true, staging = true }
local I = {
  down = "\u{F0140}", right = "\u{F0142}", folder = "\u{F024B}", branch = "\u{F062C}",
  star = "\u{F04CE}", head = "\u{F0E7}", all = "\u{F0645}", ref = "\u{F04F9}",
}
local LANES = 6 -- cores de trilha do grafo (GitLogLane1..6)

local st = {}

local function git(args)
  local cmd = { "git" }
  vim.list_extend(cmd, args)
  local r = vim.system(cmd, { cwd = st.root, text = true }):wait()
  return r.code == 0 and r.stdout or ""
end

local function lines_of(out) return vim.split(vim.trim(out or ""), "\n", { trimempty = true }) end
local function trunc(s, w)
  if w <= 0 then return "" end
  if vim.fn.strdisplaywidth(s) <= w then return s end
  return vim.fn.strcharpart(s, 0, math.max(0, w - 1)) .. "…"
end
local function pad(s, w) return s .. string.rep(" ", math.max(0, w - vim.fn.strdisplaywidth(s))) end
local function esc(s) return (s:gsub("%%", "%%%%")) end

local function set_lines(buf, text, marks)
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

-- "Hoje 15:55", "Ontem 10:02" ou "09/10/26, 18:01"
local function nice_date(ts)
  local t = tonumber(ts) or 0
  local today = os.date("*t")
  local midnight = os.time({ year = today.year, month = today.month, day = today.day, hour = 0 })
  if t >= midnight then return "Hoje " .. os.date("%H:%M", t) end
  if t >= midnight - 86400 then return "Ontem " .. os.date("%H:%M", t) end
  return os.date("%d/%m/%y, %H:%M", t)
end

local function short_refs(d)
  if not d or d == "" then return "" end
  local refs = {}
  for r in d:gmatch("[^,]+") do
    r = vim.trim(r):gsub("^HEAD %-> ", ""):gsub("^tag: ", "")
    if r ~= "HEAD" and r ~= "" then table.insert(refs, r) end
  end
  if #refs == 0 then return "" end
  return I.ref .. " " .. table.concat(refs, ", ", 1, math.min(2, #refs)) .. (#refs > 2 and " +" .. (#refs - 2) or "")
end

-- ---------------------------------------------------------------------------
-- Árvore de branches (esquerda)
-- ---------------------------------------------------------------------------
local function load_branches()
  st.current = vim.trim(git({ "branch", "--show-current" }))
  st.locals = lines_of(git({ "for-each-ref", "--format=%(refname:short)", "refs/heads" }))
  st.remotes = {}
  for _, r in ipairs(lines_of(git({ "for-each-ref", "--format=%(refname:short)", "refs/remotes" }))) do
    if r:find("/") and not r:match("/HEAD$") then table.insert(st.remotes, r) end
  end
end

-- agrupa "pasta/resto" por pasta; favoritos primeiro
local function grouped(names, strip)
  local plain, folders, order = {}, {}, {}
  for _, n in ipairs(names) do
    local shown = strip and n:gsub("^[^/]+/", "", 1) or n
    local folder, rest = shown:match("^([^/]+)/(.+)$")
    if folder then
      if not folders[folder] then folders[folder] = {}; table.insert(order, folder) end
      table.insert(folders[folder], { ref = n, label = rest })
    else
      table.insert(plain, { ref = n, label = shown, fav = FAVORITES[shown] })
    end
  end
  table.sort(plain, function(a, b)
    if a.fav ~= b.fav then return a.fav and true or false end
    return a.label < b.label
  end)
  table.sort(order)
  return plain, folders, order
end

local function build_tree()
  local items = {
    { kind = "ref", ref = "--all", label = "Todas as branches", icon = I.all, level = 0 },
    { kind = "ref", ref = "HEAD", label = "HEAD (" .. (st.current ~= "" and st.current or "detached") .. ")", icon = I.head, level = 0 },
  }
  local function section(id, label, names, strip, level, prefix)
    local key = prefix .. id
    table.insert(items, { kind = "group", id = key, label = label, level = level })
    if st.collapsed[key] then return end
    local plain, folders, order = grouped(names, strip)
    for _, b in ipairs(plain) do
      table.insert(items, { kind = "ref", ref = b.ref, label = b.label, icon = b.fav and I.star or I.branch, fav = b.fav, level = level + 1 })
    end
    for _, f in ipairs(order) do
      local fkey = key .. "/" .. f
      table.insert(items, { kind = "group", id = fkey, label = f, level = level + 1, folder = true })
      if not st.collapsed[fkey] then
        for _, b in ipairs(folders[f]) do
          table.insert(items, { kind = "ref", ref = b.ref, label = b.label, icon = I.branch, level = level + 2 })
        end
      end
    end
  end
  section("local", "Local", st.locals, false, 0, "")
  -- remotos: um grupo por remoto (origin…)
  local by_remote, rorder = {}, {}
  for _, r in ipairs(st.remotes) do
    local name = r:match("^([^/]+)/")
    if not by_remote[name] then by_remote[name] = {}; table.insert(rorder, name) end
    table.insert(by_remote[name], r)
  end
  if #rorder > 0 then
    table.insert(items, { kind = "group", id = "remote", label = "Remote", level = 0 })
    if not st.collapsed["remote"] then
      for _, name in ipairs(rorder) do section(name, name, by_remote[name], true, 1, "remote/") end
    end
  end
  return items
end

local function render_tree()
  st.tree = build_tree()
  local width = vim.api.nvim_win_get_width(st.win.tree)
  local text, marks = {}, {}
  for i, it in ipairs(st.tree) do
    local indent = string.rep("  ", it.level)
    local line
    if it.kind == "group" then
      local arrow = st.collapsed[it.id] and I.right or I.down
      local icon = it.folder and (I.folder .. " ") or ""
      line = " " .. indent .. arrow .. " " .. icon .. it.label
      table.insert(marks, { i - 1, 0, -1, it.folder and "GitLogFolder" or "GitLogGroup" })
    else
      line = " " .. indent .. it.icon .. " " .. trunc(it.label, width - #indent - 5)
      local s0 = 1 + #indent
      table.insert(marks, { i - 1, s0, s0 + #it.icon, it.fav and "GitLogStar" or (it.ref == "HEAD" and "GitLogHead" or "GitLogIcon") })
      local selected = it.ref == st.ref
      local is_cur = it.ref == st.current
      table.insert(marks, { i - 1, s0 + #it.icon, -1, selected and "GitLogRefSelected" or (is_cur and "GitLogCurrent" or "GitLogText") })
    end
    table.insert(text, line)
  end
  set_lines(st.buf.tree, text, marks)
end

-- ---------------------------------------------------------------------------
-- Log com grafo (centro)
-- ---------------------------------------------------------------------------
local GRAPH_CHARS = { ["*"] = "\u{25CF}", ["|"] = "\u{2502}", ["/"] = "\u{2571}", ["\\"] = "\u{2572}", ["-"] = "\u{2500}", ["_"] = "\u{2500}" }

local function load_log()
  local args = { "log", "--graph", "--date-order", "-n", "400",
    "--format=%x1f%H%x1f%an%x1f%ae%x1f%at%x1f%s%x1f%D%x1f%P" }
  if st.ref == "--all" then
    -- branches, remotos e tags (sem os commits internos do stash, como no PhpStorm)
    vim.list_extend(args, { "--branches", "--remotes", "--tags", "HEAD" })
  else
    table.insert(args, st.ref)
  end
  st.rows = {}
  for line in git(args):gmatch("[^\n]+") do
    local graph, rest = line:match("^([^\31]*)\31(.*)$")
    local row = { graph = (graph or line):gsub("%s+$", "") }
    if rest then
      local h, an, ae, at, s, d, p = rest:match("^(.-)\31(.-)\31(.-)\31(.-)\31(.-)\31(.-)\31(.*)$")
      if h then
        row.commit = {
          hash = h, author = an, email = ae, ts = at, date = nice_date(at), subject = s,
          refs = short_refs(d), head = d:match("^HEAD") ~= nil,
          merge = #vim.split(p, " ", { trimempty = true }) > 1,
        }
      end
    end
    table.insert(st.rows, row)
  end
end

local function visible_rows()
  if not st.filter or st.filter == "" then return st.rows end
  -- com busca: só os commits que batem (sem as linhas de ligação do grafo)
  local q, out = st.filter:lower(), {}
  for _, r in ipairs(st.rows) do
    local c = r.commit
    if c and (c.subject:lower():find(q, 1, true) or c.author:lower():find(q, 1, true) or c.hash:find(q, 1, true) == 1) then
      table.insert(out, r)
    end
  end
  return out
end

local function render_log()
  local rows = visible_rows()
  st.shown = rows
  local width = vim.api.nvim_win_get_width(st.win.log)
  local gw = 0
  for _, r in ipairs(rows) do gw = math.max(gw, vim.fn.strchars(r.graph)) end
  gw = math.min(gw, GRAPH_MAX)
  local text, marks = {}, {}
  for i, r in ipairs(rows) do
    local c = r.commit
    local mine = c and c.author == st.me
    local author = pad(c and trunc(c.author, AUTHOR_W) or "", AUTHOR_W)
    local date = pad(c and c.date or "", DATE_W)
    -- grafo: troca os caracteres ASCII por linhas finas e pinta cada trilha
    local g, gm = "", {}
    local raw = vim.fn.strcharpart(r.graph, 0, gw)
    for col = 0, vim.fn.strchars(raw) - 1 do
      local ch = vim.fn.strcharpart(raw, col, 1)
      local out = GRAPH_CHARS[ch] or ch
      if ch == "*" and c and c.head then out = "\u{25C9}" end -- ◉ commit atual
      if ch == "*" and c and c.merge then out = "\u{25CB}" end -- ○ merge
      local lane = (math.floor(col / 2) % LANES) + 1
      if out ~= " " then table.insert(gm, { #g, #g + #out, ch == "*" and c and c.head and "GitLogHeadDot" or ("GitLogLane" .. lane) }) end
      g = g .. out
    end
    g = pad(g, gw)
    local left = " " .. author .. " " .. date .. " " .. g .. "  "
    local line = left
    if c then
      -- refs com largura limitada: o título do commit é o que mais importa
      local refs = c.refs ~= "" and trunc(c.refs, math.min(32, math.floor(width * 0.2))) or ""
      local room = width - vim.fn.strdisplaywidth(left) - (refs ~= "" and vim.fn.strdisplaywidth(refs) + 3 or 1)
      local subject = trunc(c.subject, room)
      line = left .. subject
      if refs ~= "" then line = pad(line, width - vim.fn.strdisplaywidth(refs) - 1) .. refs end
      local a0, d0 = 1, 1 + #author + 1
      local g0 = d0 + #date + 1
      local s0 = g0 + #g + 2
      local hl = c.merge and "GitLogMerge"
      table.insert(marks, { i - 1, a0, a0 + #author, hl or (mine and "GitLogAuthorMe" or "GitLogAuthor") })
      table.insert(marks, { i - 1, d0, d0 + #date, hl or "GitLogDate" })
      table.insert(marks, { i - 1, s0, s0 + #subject, hl or "GitLogSubject" })
      if refs ~= "" then table.insert(marks, { i - 1, #line - #refs, #line, "GitLogRefs" }) end
      for _, m in ipairs(gm) do table.insert(marks, { i - 1, g0 + m[1], g0 + m[2], m[3] }) end
    else
      local g0 = 1 + #author + 1 + #date + 1
      for _, m in ipairs(gm) do table.insert(marks, { i - 1, g0 + m[1], g0 + m[2], m[3] }) end
    end
    table.insert(text, line)
  end
  if #text == 0 then
    text = { "", "   Nenhum commit encontrado" .. (st.filter and (" para \"" .. st.filter .. "\"") or "") }
    table.insert(marks, { 1, 0, -1, "GitLogEmpty" })
  end
  set_lines(st.buf.log, text, marks)
  local label = st.ref == "--all" and "Todas as branches" or (st.ref == "HEAD" and ("HEAD (" .. st.current .. ")") or st.ref)
  vim.wo[st.win.log].winbar = "%#GitLogBar# Log  %#GitLogBarStrong#" .. esc(label) .. "%#GitLogBar#"
    .. (st.filter and ("   busca: %#GitLogBarStrong#" .. esc(st.filter) .. "%#GitLogBar#  (Esc limpa)") or "")
    .. "%=/ busca   r recarrega "
end

-- ---------------------------------------------------------------------------
-- Arquivos e detalhes do commit (direita)
-- ---------------------------------------------------------------------------
local STATUS_HL = { M = "GitLogFileM", A = "GitLogFileA", D = "GitLogFileD", R = "GitLogFileR", C = "GitLogFileR" }

local function render_commit(c)
  if st.commit_shown == (c and c.hash or "none") then return end
  st.commit_shown = c and c.hash or "none"
  st.files = {}
  local text, marks = {}, {}
  if not c then
    text = { "", "  Selecione um commit para ver os arquivos" }
    table.insert(marks, { 1, 0, -1, "GitLogEmpty" })
    set_lines(st.buf.files, text, marks)
    set_lines(st.buf.details, {}, {})
    vim.wo[st.win.files].winbar = "%#GitLogBar# Arquivos"
    return
  end
  -- arquivos agrupados por pasta
  local list = {}
  for line in git({ "diff", "--name-status", "-M", c.hash .. "^", c.hash }):gmatch("[^\n]+") do
    local p = vim.split(line, "\t", { plain = true })
    table.insert(list, { status = p[1]:sub(1, 1), path = p[3] or p[2], old = p[2] })
  end
  if #list == 0 and not c.merge then
    -- primeiro commit do repositório (sem pai)
    for line in git({ "show", "--name-status", "--format=", c.hash }):gmatch("[^\n]+") do
      local p = vim.split(line, "\t", { plain = true })
      table.insert(list, { status = p[1]:sub(1, 1), path = p[3] or p[2], old = p[2] })
    end
  end
  local dirs, order = {}, {}
  for _, f in ipairs(list) do
    local d = vim.fn.fnamemodify(f.path, ":h")
    if not dirs[d] then dirs[d] = {}; table.insert(order, d) end
    table.insert(dirs[d], f)
  end
  table.sort(order)
  for _, d in ipairs(order) do
    local n = #dirs[d]
    local label = " " .. I.folder .. " " .. (d == "." and "(raiz)" or d)
    local count = "  " .. n .. " arquivo" .. (n == 1 and "" or "s")
    table.insert(text, label .. count)
    table.insert(marks, { #text - 1, 0, #label, "GitLogFolder" })
    table.insert(marks, { #text - 1, #label, -1, "GitLogMeta" })
    for _, f in ipairs(dirs[d]) do
      local name = vim.fn.fnamemodify(f.path, ":t")
      table.insert(text, "     " .. f.status .. "  " .. name)
      st.files[#text] = { commit = c.hash, status = f.status, path = f.path, old = f.old }
      table.insert(marks, { #text - 1, 5, 6, STATUS_HL[f.status] or "GitLogMeta" })
      table.insert(marks, { #text - 1, 8, -1, "GitLogSubject" })
    end
  end
  if #text == 0 then text = { "", "  Nenhum arquivo alterado (merge sem conflito)" }; table.insert(marks, { 1, 0, -1, "GitLogEmpty" }) end
  set_lines(st.buf.files, text, marks)
  vim.wo[st.win.files].winbar = "%#GitLogBar# Arquivos  %#GitLogBarStrong#" .. #list .. "%#GitLogBar#"

  -- detalhes: mensagem, hash, autor, data
  local body = lines_of(git({ "show", "-s", "--format=%B", c.hash }))
  local dtext, dmarks = {}, {}
  for i, l in ipairs(body) do
    table.insert(dtext, " " .. l)
    if i == 1 then table.insert(dmarks, { #dtext - 1, 0, -1, "GitLogTitle" }) end
  end
  table.insert(dtext, "")
  table.insert(dtext, " " .. c.hash:sub(1, 10) .. "  " .. c.author .. " <" .. c.email .. ">")
  table.insert(dmarks, { #dtext - 1, 0, -1, "GitLogMeta" })
  table.insert(dtext, " " .. os.date("%d/%m/%Y às %H:%M", tonumber(c.ts)))
  table.insert(dmarks, { #dtext - 1, 0, -1, "GitLogMeta" })
  local contains = lines_of(git({ "branch", "--contains", c.hash, "--format=%(refname:short)" }))
  if #contains > 0 then
    table.insert(dtext, "")
    table.insert(dtext, " Em " .. #contains .. " branch" .. (#contains == 1 and "" or "es") .. ": "
      .. table.concat(contains, ", ", 1, math.min(4, #contains)) .. (#contains > 4 and " …" or ""))
    table.insert(dmarks, { #dtext - 1, 0, -1, "GitLogMeta" })
  end
  set_lines(st.buf.details, dtext, dmarks)
end

local function selected_commit()
  local r = st.shown and st.shown[vim.api.nvim_win_get_cursor(st.win.log)[1]]
  return r and r.commit
end

-- ---------------------------------------------------------------------------
-- Ações
-- ---------------------------------------------------------------------------
local function select_ref(ref)
  st.ref, st.filter, st.commit_shown = ref, nil, nil
  load_log()
  render_tree()
  render_log()
  pcall(vim.api.nvim_win_set_cursor, st.win.log, { 1, 0 })
  -- primeira linha com commit
  for i, r in ipairs(st.shown) do
    if r.commit then pcall(vim.api.nvim_win_set_cursor, st.win.log, { i, 0 }); break end
  end
  render_commit(selected_commit())
end

local function refresh()
  load_branches()
  select_ref(st.ref)
end

local function tree_activate(line)
  local it = st.tree[line or vim.api.nvim_win_get_cursor(st.win.tree)[1]]
  if not it then return end
  if it.kind == "group" then
    st.collapsed[it.id] = not st.collapsed[it.id]
    return render_tree()
  end
  select_ref(it.ref)
end

local function search()
  vim.ui.input({ prompt = "Buscar no log (texto, autor ou hash): ", default = st.filter or "" }, function(q)
    if q == nil then return end
    q = vim.trim(q)
    st.filter = q ~= "" and q or nil
    st.commit_shown = nil
    render_log()
    pcall(vim.api.nvim_win_set_cursor, st.win.log, { 1, 0 })
    render_commit(selected_commit())
    vim.api.nvim_set_current_win(st.win.log)
  end)
end

local function open_file()
  local f = st.files and st.files[vim.api.nvim_win_get_cursor(st.win.files)[1]]
  if f then require("config.git_compare").file_diff(st.root, f) end
end

-- ---------------------------------------------------------------------------
-- Janela
-- ---------------------------------------------------------------------------
local function style(win, opts)
  local wo = vim.wo[win]
  wo.number, wo.relativenumber, wo.signcolumn, wo.statuscolumn = false, false, "no", ""
  wo.foldcolumn, wo.foldenable, wo.list, wo.spell = "0", false, false, false
  wo.wrap, wo.linebreak = opts.wrap or false, opts.wrap or false
  wo.cursorline = opts.cursorline ~= false
  wo.winfixwidth = opts.fixw or false
  wo.winhighlight = "Normal:GitLogPanel,NormalNC:GitLogPanel,CursorLine:GitLogSel,WinBar:GitLogBar,WinBarNC:GitLogBar,EndOfBuffer:GitLogPanel"
end

local function scratch(name)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "git_log"
  pcall(vim.api.nvim_buf_set_name, buf, "Git: " .. name)
  return buf
end

function M.is_open()
  return st.tab and vim.api.nvim_tabpage_is_valid(st.tab) and vim.api.nvim_get_current_tabpage() == st.tab
end

function M.close()
  if st.tab and vim.api.nvim_tabpage_is_valid(st.tab) then
    vim.api.nvim_set_current_tabpage(st.tab)
    pcall(vim.cmd, "tabclose")
  end
  st = {}
end

function M.open()
  if st.tab and vim.api.nvim_tabpage_is_valid(st.tab) then
    return vim.api.nvim_set_current_tabpage(st.tab)
  end
  local r = vim.system({ "git", "rev-parse", "--show-toplevel" }, { cwd = vim.fn.getcwd(), text = true }):wait()
  if r.code ~= 0 then return vim.notify("Esta pasta não é um repositório git", vim.log.levels.WARN, { title = "Git" }) end
  st = { root = vim.trim(r.stdout), ref = "--all", collapsed = {}, buf = {}, win = {} }
  st.me = vim.trim(git({ "config", "user.name" }))
  load_branches()
  -- pastas e remotos começam recolhidos; Local aberto
  for _, n in ipairs(st.locals) do local f = n:match("^([^/]+)/"); if f then st.collapsed["local/" .. f] = true end end
  for _, n in ipairs(st.remotes) do
    local rem, folder = n:match("^([^/]+)/([^/]+)/")
    if rem then st.collapsed["remote/" .. rem .. "/" .. folder] = true end
  end

  vim.cmd("tabnew")
  st.tab = vim.api.nvim_get_current_tabpage()
  vim.t.no_activity_bar = true
  local placeholder = vim.api.nvim_get_current_buf()

  st.win.log = vim.api.nvim_get_current_win()
  st.buf.log = scratch("log")
  vim.api.nvim_win_set_buf(st.win.log, st.buf.log)
  if placeholder ~= st.buf.log and vim.api.nvim_buf_is_valid(placeholder) then pcall(vim.api.nvim_buf_delete, placeholder, { force = true }) end

  vim.cmd("topleft vsplit")
  st.win.tree = vim.api.nvim_get_current_win()
  st.buf.tree = scratch("branches")
  vim.api.nvim_win_set_buf(st.win.tree, st.buf.tree)
  vim.api.nvim_win_set_width(st.win.tree, 32)

  vim.api.nvim_set_current_win(st.win.log)
  vim.cmd("botright vsplit")
  st.win.files = vim.api.nvim_get_current_win()
  st.buf.files = scratch("arquivos")
  vim.api.nvim_win_set_buf(st.win.files, st.buf.files)
  vim.api.nvim_win_set_width(st.win.files, math.max(40, math.floor(vim.o.columns * 0.26)))
  vim.cmd("belowright split")
  st.win.details = vim.api.nvim_get_current_win()
  st.buf.details = scratch("detalhes")
  vim.api.nvim_win_set_buf(st.win.details, st.buf.details)
  vim.api.nvim_win_set_height(st.win.details, math.floor(vim.o.lines * 0.35))

  style(st.win.tree, { fixw = true })
  style(st.win.log, {})
  style(st.win.files, { fixw = true })
  style(st.win.details, { wrap = true, cursorline = false })
  vim.wo[st.win.tree].winbar = "%#GitLogBar# Branches"
  vim.wo[st.win.details].winbar = "%#GitLogBar# Detalhes"

  -- teclas
  local function map(buf, lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true }) end
  local order = { "tree", "log", "files", "details" }
  for idx, k in ipairs(order) do
    local b = st.buf[k]
    map(b, "q", M.close)
    map(b, "<Tab>", function() vim.api.nvim_set_current_win(st.win[order[idx % #order + 1]]) end)
    map(b, "<S-Tab>", function() vim.api.nvim_set_current_win(st.win[order[(idx - 2) % #order + 1]]) end)
    map(b, "/", search)
    map(b, "r", refresh)
  end
  map(st.buf.tree, "<CR>", function() tree_activate() end)
  map(st.buf.tree, "<LeftRelease>", function()
    local p = vim.fn.getmousepos()
    if p.winid == st.win.tree then tree_activate(p.line) end
  end)
  map(st.buf.log, "<CR>", function() vim.api.nvim_set_current_win(st.win.files) end)
  map(st.buf.log, "<Esc>", function()
    if st.filter then st.filter, st.commit_shown = nil, nil; render_log(); render_commit(selected_commit()) end
  end)
  map(st.buf.files, "<CR>", open_file)
  map(st.buf.files, "<2-LeftMouse>", open_file)

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = st.buf.log,
    callback = function() render_commit(selected_commit()) end,
  })
  vim.api.nvim_create_autocmd("WinResized", {
    callback = function()
      if not (st.buf.log and vim.api.nvim_buf_is_valid(st.buf.log)) then return true end
      if vim.api.nvim_win_is_valid(st.win.log) then render_log() end
    end,
  })
  vim.api.nvim_create_autocmd("TabClosed", {
    callback = function()
      if st.tab and not vim.api.nvim_tabpage_is_valid(st.tab) then st = {}; return true end
    end,
  })

  select_ref("--all")
  vim.api.nvim_set_current_win(st.win.log)
  -- q, Cmd+W, :q ou fechar uma coluna fecham a janela de Git inteira
  require("config.git_compare").own_tab(st.tab)
end

-- Botão Git da barra lateral e atalhos: abre; se já estiver nela, fecha
function M.toggle()
  if M.is_open() then return M.close() end
  M.open()
end

local function colors()
  local ok, c = pcall(require, "config.palette")
  if not ok then return end
  local set = vim.api.nvim_set_hl
  set(0, "GitLogPanel", { fg = c.fg, bg = c.bg })
  set(0, "GitLogBar", { fg = c.fg_dim, bg = c.bg_alt })
  set(0, "GitLogBarStrong", { fg = "#DFE1E5", bg = c.bg_alt, bold = true })
  set(0, "GitLogSel", { bg = "#2E436E" })
  set(0, "GitLogGroup", { fg = c.fg, bold = true })
  set(0, "GitLogFolder", { fg = c.fg })
  set(0, "GitLogIcon", { fg = c.fg_dim })
  set(0, "GitLogStar", { fg = "#E8B647" })
  set(0, "GitLogHead", { fg = c.hint })
  set(0, "GitLogText", { fg = c.fg })
  set(0, "GitLogCurrent", { fg = c.fg, bold = true })
  set(0, "GitLogRefSelected", { fg = "#FFFFFF", bold = true, underline = true, sp = c.accent })
  set(0, "GitLogAuthor", { fg = c.fg })
  set(0, "GitLogAuthorMe", { fg = "#DFE1E5", bold = true })
  set(0, "GitLogDate", { fg = c.fg_dim })
  set(0, "GitLogSubject", { fg = c.fg })
  set(0, "GitLogMerge", { fg = c.fg_faint })
  set(0, "GitLogRefs", { fg = c.fg_faint })
  set(0, "GitLogEmpty", { fg = c.fg_faint })
  set(0, "GitLogTitle", { fg = "#DFE1E5", bold = true })
  set(0, "GitLogMeta", { fg = c.fg_dim })
  set(0, "GitLogFileM", { fg = c.change })
  set(0, "GitLogFileA", { fg = c.add })
  set(0, "GitLogFileD", { fg = c.error })
  set(0, "GitLogFileR", { fg = c.warn })
  set(0, "GitLogHeadDot", { fg = c.hint })
  -- trilhas do grafo, como as linhas coloridas do PhpStorm
  local lanes = { c.variable, c.method, c.hint, c.tag, c.field, c.static }
  for i, color in ipairs(lanes) do set(0, "GitLogLane" .. i, { fg = color }) end
end
colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = colors })

return M
