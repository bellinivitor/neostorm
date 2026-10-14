-- Janela de Git no estilo da tool window de Git do PhpStorm (tema Islands): painel embaixo,
-- com metade da altura, e o código continua visível em cima. Cada coluna é uma ilha sobre
-- um fundo mais escuro:
--   ╭ Branches ────╮ ╭ Log  Todas as branches  412 commits ──── / Buscar  r Atualizar  q Fechar ╮ ╭ Commit  25 arquivos ─╮
--   │▍Todas        │ │ ●  feat/x  Corrige o cálculo…          Vitor   Hoje 15:55   a62cd9d     │ │ título do commit     │
--   │ Branch atual │ │ │╲ Merge branch 'dev'                   Yuri    Ontem 10:02  91b0e2f     │ │ autor, data, hash    │
--   │ ▾ Local   12 │ │ …                                                                       │ │ ──────────────────── │
--   ╰──────────────╯ ╰─────────────────────────────────────────────────────────────────────────╯ │ 󰉋 app/Models      1  │
-- Enter: na árvore escolhe a branch (ou abre/fecha a pasta); no log vai para os arquivos;
-- num arquivo abre o diff. / busca por texto, autor ou hash. r atualiza. Tab troca de ilha.
-- m (ou botão direito) abre as ações: no commit (cherry-pick, revert, reset, nova branch…)
-- e na branch (checkout, merge, rebase…). Esc limpa a busca (ou volta para o código). q fecha.
local M = {}

local ns = vim.api.nvim_create_namespace("git_log")
local AUTHOR_W, DATE_W, HASH_W, GRAPH_MAX, CHIP_MAX = 16, 14, 7, 16, 26
local HEIGHT = 0.5 -- metade da altura da tela
local FAVORITES = { main = true, master = true, develop = true, dev = true, staging = true }
local I = {
  down = "\u{F0140}", right = "\u{F0142}", folder = "\u{F024B}", branch = "\u{F062C}",
  star = "\u{F04CE}", head = "\u{F0E7}", all = "\u{F0645}", tag = "\u{F04F9}",
  user = "\u{F0004}", clock = "\u{F0150}", hash = "\u{F0423}", bar = "\u{258D}",
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
local function dw(s) return vim.fn.strdisplaywidth(s) end
local function trunc(s, w)
  if w <= 0 then return "" end
  if dw(s) <= w then return s end
  return vim.fn.strcharpart(s, 0, math.max(0, w - 1)) .. "…"
end
local function pad(s, w) return s .. string.rep(" ", math.max(0, w - dw(s))) end
local function esc(s) return (s:gsub("%%", "%%%%")) end
local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

-- Linha com destaques: L = { s = texto, marks = { {ini, fim, hl} }, line_hl = grupo da linha inteira }
local function new_line() return { s = "", marks = {} } end
local function put(L, text, hl)
  local s0 = #L.s
  L.s = L.s .. text
  if hl and #text > 0 then table.insert(L.marks, { s0, #L.s, hl }) end
  return L
end
-- completa com espaços até sobrar exatamente `right_w` colunas no fim
local function fill(L, width, right_w) put(L, string.rep(" ", math.max(1, width - dw(L.s) - right_w))) end

local function set_lines(buf, lines)
  local text = {}
  for i, L in ipairs(lines) do text[i] = L.s end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i, L in ipairs(lines) do
    if L.line_hl then vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { line_hl_group = L.line_hl }) end
    for _, m in ipairs(L.marks) do
      vim.api.nvim_buf_set_extmark(buf, ns, i - 1, m[1], { end_col = m[2], hl_group = m[3] })
    end
  end
end

local function message(text)
  return { new_line(), put(new_line(), "   " .. text, "GitLogEmpty") }
end

-- "Hoje 15:55", "Ontem 10:02" ou "09/10/26 18:01"
local function nice_date(ts)
  local t = tonumber(ts) or 0
  local today = os.date("*t")
  local midnight = os.time({ year = today.year, month = today.month, day = today.day, hour = 0 })
  if t >= midnight then return "Hoje " .. os.date("%H:%M", t) end
  if t >= midnight - 86400 then return "Ontem " .. os.date("%H:%M", t) end
  return os.date("%d/%m/%y %H:%M", t)
end

-- Refs do commit viram etiquetas: branch atual, local, remota e tag.
-- Uma remota com o mesmo nome de uma branch local não aparece repetida.
local function parse_refs(d)
  local list, locals = {}, {}
  for r in (d or ""):gmatch("[^,]+") do
    r = vim.trim(r)
    local kind
    if r:match("^HEAD %-> ") then r, kind = r:gsub("^HEAD %-> ", ""), "head"
    elseif r:match("^tag: ") then r, kind = r:gsub("^tag: ", ""), "tag"
    elseif r == "HEAD" or r:match("/HEAD$") then r = nil
    elseif st.remote_names[r:match("^([^/]+)/") or ""] then kind = "remote"
    else kind = "local" end
    if r then
      table.insert(list, { name = r, kind = kind })
      if kind == "local" or kind == "head" then locals[r] = true end
    end
  end
  local out = {}
  for _, ref in ipairs(list) do
    local short = ref.kind == "remote" and ref.name:gsub("^[^/]+/", "", 1)
    if not (short and locals[short]) then table.insert(out, ref) end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Árvore de branches (esquerda)
-- ---------------------------------------------------------------------------
local function load_branches()
  st.current = vim.trim(git({ "branch", "--show-current" }))
  st.locals = lines_of(git({ "for-each-ref", "--format=%(refname:short)", "refs/heads" }))
  st.remote_names = {}
  for _, r in ipairs(lines_of(git({ "remote" }))) do st.remote_names[r] = true end
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
    { kind = "ref", ref = "HEAD", label = "Branch atual", hint = st.current ~= "" and st.current or "detached", icon = I.head, level = 0 },
  }
  local function section(id, label, names, strip, level, prefix)
    local key = prefix .. id
    table.insert(items, { kind = "group", id = key, label = label, count = #names, level = level })
    if st.collapsed[key] then return end
    local plain, folders, order = grouped(names, strip)
    for _, b in ipairs(plain) do
      table.insert(items, { kind = "ref", ref = b.ref, label = b.label, icon = b.fav and I.star or I.branch, fav = b.fav, level = level + 1 })
    end
    for _, f in ipairs(order) do
      local fkey = key .. "/" .. f
      table.insert(items, { kind = "group", id = fkey, label = f, count = #folders[f], level = level + 1, folder = true })
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
    table.insert(items, { kind = "group", id = "remote", label = "Remotas", count = #st.remotes, level = 0 })
    if not st.collapsed["remote"] then
      for _, name in ipairs(rorder) do section(name, name, by_remote[name], true, 1, "remote/") end
    end
  end
  return items
end

local function render_tree()
  st.tree = build_tree()
  local width = vim.api.nvim_win_get_width(st.win.tree)
  local lines = {}
  for _, it in ipairs(st.tree) do
    local L = new_line()
    local selected = it.kind == "ref" and it.ref == st.ref
    -- a branch mostrada no log ganha uma barra de destaque na borda
    put(L, selected and I.bar or " ", selected and "GitLogAccent" or nil)
    put(L, string.rep("  ", it.level))
    if it.kind == "group" then
      put(L, (st.collapsed[it.id] and I.right or I.down) .. " ", "GitLogArrow")
      if it.folder then put(L, I.folder .. " ", "GitLogIcon") end
      local count = tostring(it.count)
      put(L, trunc(it.label, width - dw(L.s) - #count - 2), it.folder and "GitLogFolder" or "GitLogGroup")
      fill(L, width, #count + 1)
      put(L, count, "GitLogCount")
    else
      local is_cur = it.ref == st.current
      put(L, it.icon .. " ", it.fav and "GitLogStar" or ((it.ref == "HEAD" or is_cur) and "GitLogHead" or "GitLogIcon"))
      local room = width - dw(L.s) - 1
      put(L, trunc(it.label, room), selected and "GitLogRefSelected" or (is_cur and "GitLogCurrent" or "GitLogText"))
      if it.hint and room - dw(it.label) > 4 then put(L, "  " .. trunc(it.hint, room - dw(it.label) - 2), "GitLogCount") end
      if selected then L.line_hl = "GitLogTreeSel" end
    end
    table.insert(lines, L)
  end
  set_lines(st.buf.tree, lines)
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
  st.rows, st.count = {}, 0
  for line in git(args):gmatch("[^\n]+") do
    local graph, rest = line:match("^([^\31]*)\31(.*)$")
    local row = { graph = (graph or line):gsub("%s+$", "") }
    if rest then
      local h, an, ae, at, s, d, p = rest:match("^(.-)\31(.-)\31(.-)\31(.-)\31(.-)\31(.-)\31(.*)$")
      if h then
        row.commit = {
          hash = h, author = an, email = ae, ts = at, date = nice_date(at), subject = s,
          refs = parse_refs(d), head = d:match("^HEAD") ~= nil,
          merge = #vim.split(p, " ", { trimempty = true }) > 1,
        }
        st.count = st.count + 1
      end
    end
    -- linhas do grafo só com trilhas retas não dizem nada: viravam buracos no log
    if row.commit or not row.graph:match("^[|%s]*$") then table.insert(st.rows, row) end
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

local CHIP_HL = { head = "GitLogChipHead", ["local"] = "GitLogChipLocal", remote = "GitLogChipRemote", tag = "GitLogChipTag" }

local function chips_of(c)
  local out, w = {}, 0
  for i, ref in ipairs(c.refs) do
    if i > 2 then
      local more = "+" .. (#c.refs - 2)
      table.insert(out, { more, "GitLogCount" })
      w = w + #more + 1
      break
    end
    local text = " " .. (ref.kind == "tag" and (I.tag .. " ") or "") .. trunc(ref.name, CHIP_MAX) .. " "
    table.insert(out, { text, CHIP_HL[ref.kind] })
    w = w + dw(text) + 1
  end
  return out, w
end

local function render_log()
  local rows = visible_rows()
  st.shown = rows
  local width = vim.api.nvim_win_get_width(st.win.log)
  -- colunas da direita somem quando o painel fica estreito; o título tem prioridade
  local show_hash, show_author = width >= 100, width >= 76
  local right_w = DATE_W + 1 + (show_author and AUTHOR_W + 2 or 0) + (show_hash and HASH_W + 2 or 0)
  local gw = 0
  for _, r in ipairs(rows) do gw = math.max(gw, vim.fn.strchars(r.graph)) end
  gw = math.min(gw, GRAPH_MAX)
  local lines = {}
  for _, r in ipairs(rows) do
    local c = r.commit
    local L = put(new_line(), "  ")
    -- grafo: troca os caracteres ASCII por linhas finas e pinta cada trilha
    local raw = vim.fn.strcharpart(r.graph, 0, gw)
    for col = 0, vim.fn.strchars(raw) - 1 do
      local ch = vim.fn.strcharpart(raw, col, 1)
      local out = GRAPH_CHARS[ch] or ch
      local hl = "GitLogLane" .. ((math.floor(col / 2) % LANES) + 1)
      if ch == "*" and c then
        if c.merge then out = "\u{25CB}" end -- ○ merge
        if c.head then out, hl = "\u{25C9}", "GitLogHeadDot" end -- ◉ commit atual
      end
      put(L, out, out ~= " " and hl or nil)
    end
    put(L, string.rep(" ", gw - vim.fn.strchars(raw) + 2))
    if c then
      local chips, chips_w = chips_of(c)
      local room = width - dw(L.s) - right_w - 2
      if room - chips_w < 16 then chips, chips_w = {}, 0 end
      for _, ch in ipairs(chips) do put(L, ch[1], ch[2]); put(L, " ") end
      put(L, trunc(c.subject, room - chips_w), c.merge and "GitLogMerge" or "GitLogSubject")
      fill(L, width, right_w)
      if show_author then
        local unknown = c.author == "" or c.author == "unknown"
        put(L, pad(trunc(c.author, AUTHOR_W), AUTHOR_W),
          (c.merge or unknown) and "GitLogMerge" or (c.author == st.me and "GitLogAuthorMe" or "GitLogAuthor"))
        put(L, "  ")
      end
      put(L, pad(c.date, DATE_W), "GitLogDate")
      if show_hash then put(L, "  "); put(L, c.hash:sub(1, HASH_W), "GitLogHash") end
    end
    table.insert(lines, L)
  end
  if #lines == 0 then
    lines = message(st.filter and ("Nenhum commit com \"" .. st.filter .. "\". Esc limpa a busca.") or "Nenhum commit nesta branch.")
  end
  set_lines(st.buf.log, lines)

  local label = st.ref == "--all" and "Todas as branches" or (st.ref == "HEAD" and st.current or st.ref)
  local function action(id, key, text)
    return "%" .. id .. "@v:lua.GitLogAction@%#GitLogKey# " .. key .. " %#GitLogBar# " .. text .. "%X  "
  end
  vim.wo[st.win.log].winbar = " Log   %#GitLogBarStrong#" .. esc(label) .. "%#GitLogBarDim#  " .. plural(st.count, "commit", "commits")
    .. (st.filter and ("%#GitLogBar#   busca %#GitLogFilter# " .. esc(st.filter) .. " %#GitLogBar#") or "")
    .. "%#GitLogBar#%<%="
    .. action(1, "/", "Buscar") .. action(4, "m", "Ações") .. action(2, "r", "Atualizar") .. action(3, "q", "Fechar")
end

-- ---------------------------------------------------------------------------
-- Commit selecionado: mensagem, autor e arquivos numa ilha só (direita)
-- ---------------------------------------------------------------------------
local STATUS_HL = { M = "GitLogFileM", A = "GitLogFileA", D = "GitLogFileD", R = "GitLogFileR", C = "GitLogFileR" }

local function changed_files(c)
  local range = { c.hash .. "^", c.hash }
  local status = lines_of(git(vim.list_extend({ "diff", "--name-status", "-M" }, range)))
  local stats = lines_of(git(vim.list_extend({ "diff", "--numstat", "-M" }, range)))
  if #status == 0 and not c.merge then
    -- primeiro commit do repositório (sem pai)
    status = lines_of(git({ "show", "--name-status", "--format=", c.hash }))
    stats = lines_of(git({ "show", "--numstat", "--format=", c.hash }))
  end
  local list = {}
  for i, line in ipairs(status) do
    local p = vim.split(line, "\t", { plain = true })
    local add, del = (stats[i] or ""):match("^(%S+)\t(%S+)")
    table.insert(list, { status = p[1]:sub(1, 1), path = p[3] or p[2], old = p[2], add = tonumber(add), del = tonumber(del), bin = add == "-" })
  end
  return list
end

-- quebra o texto em linhas de até `width` colunas (a mensagem do commit)
local function wrap(text, width)
  local out, cur = {}, ""
  for word in text:gmatch("%S+") do
    if cur == "" then cur = word
    elseif dw(cur) + 1 + dw(word) <= width then cur = cur .. " " .. word
    else table.insert(out, cur); cur = word end
  end
  table.insert(out, cur)
  return out
end

local function commit_header(c, width, lines)
  local body = vim.split(vim.trim(git({ "show", "-s", "--format=%B", c.hash })), "\n", { plain = true })
  for i, para in ipairs(body) do
    for _, l in ipairs(wrap(para, width - 2)) do
      table.insert(lines, put(new_line(), " " .. l, i == 1 and "GitLogTitle" or "GitLogBody"))
    end
  end
  table.insert(lines, new_line())
  local L = put(new_line(), " " .. I.user .. "  ", "GitLogIcon")
  put(L, c.author, "GitLogAuthor")
  if dw(L.s) + dw(c.email) + 2 < width then put(L, "  " .. c.email, "GitLogMeta") end
  table.insert(lines, L)
  L = put(new_line(), " " .. I.clock .. "  ", "GitLogIcon")
  put(L, os.date("%d/%m/%Y às %H:%M", tonumber(c.ts)), "GitLogMeta")
  put(L, "    " .. I.hash .. " ", "GitLogIcon"); put(L, c.hash:sub(1, 10), "GitLogHash")
  table.insert(lines, L)
  local contains = lines_of(git({ "branch", "--contains", c.hash, "--format=%(refname:short)" }))
  if #contains > 0 then
    L = put(new_line(), " " .. I.branch .. "  ", "GitLogIcon")
    local more = #contains > 3 and (" +" .. (#contains - 3)) or ""
    put(L, trunc(table.concat(contains, ", ", 1, math.min(3, #contains)), width - dw(L.s) - #more - 1) .. more, "GitLogMeta")
    table.insert(lines, L)
  end
  -- fio entre a mensagem e a lista de arquivos
  table.insert(lines, new_line())
  table.insert(lines, put(new_line(), " " .. string.rep("\u{2500}", width - 2), "GitLogRule"))
end

local function render_commit(c)
  if st.commit_shown == (c and c.hash or "none") then return end
  st.commit_shown = c and c.hash or "none"
  st.files, st.first_file = {}, nil
  if not c then
    set_lines(st.buf.info, message("Selecione um commit no log."))
    vim.wo[st.win.info].winbar = " Commit"
    return
  end
  local width = vim.api.nvim_win_get_width(st.win.info)
  local lines = {}
  commit_header(c, width, lines)

  -- arquivos agrupados por pasta, com linhas adicionadas/removidas na direita
  local list = changed_files(c)
  local dirs, order = {}, {}
  local add_total, del_total = 0, 0
  for _, f in ipairs(list) do
    local d = vim.fn.fnamemodify(f.path, ":h")
    if not dirs[d] then dirs[d] = {}; table.insert(order, d) end
    table.insert(dirs[d], f)
    add_total, del_total = add_total + (f.add or 0), del_total + (f.del or 0)
  end
  table.sort(order)
  for _, d in ipairs(order) do
    local count = tostring(#dirs[d])
    local L = put(new_line(), " " .. I.folder .. " ", "GitLogIcon")
    put(L, trunc(d == "." and "(raiz)" or d, width - dw(L.s) - #count - 2), "GitLogFolder")
    fill(L, width, #count + 1)
    put(L, count, "GitLogCount")
    table.insert(lines, L)
    for _, f in ipairs(dirs[d]) do
      local plus = f.add and f.add > 0 and ("+" .. f.add) or ""
      local minus = f.del and f.del > 0 and ("\u{2212}" .. f.del) or ""
      local stat = f.bin and "bin" or vim.trim(plus .. " " .. minus)
      L = put(new_line(), "    ")
      put(L, f.status, STATUS_HL[f.status] or "GitLogMeta")
      put(L, "  ")
      put(L, trunc(vim.fn.fnamemodify(f.path, ":t"), width - dw(L.s) - dw(stat) - 2), f.status == "D" and "GitLogDeleted" or "GitLogText")
      if stat ~= "" then
        fill(L, width, dw(stat) + 1)
        if f.bin then
          put(L, stat, "GitLogCount")
        else
          put(L, plus, "GitLogFileA")
          if plus ~= "" and minus ~= "" then put(L, " ") end
          put(L, minus, "GitLogDel")
        end
      end
      table.insert(lines, L)
      st.files[#lines] = { commit = c.hash, status = f.status, path = f.path, old = f.old }
      st.first_file = st.first_file or #lines
    end
  end
  if #list == 0 then table.insert(lines, put(new_line(), " Merge sem mudanças próprias.", "GitLogEmpty")) end
  set_lines(st.buf.info, lines)
  pcall(vim.api.nvim_win_set_cursor, st.win.info, { st.first_file or 1, 0 })
  vim.wo[st.win.info].winbar = " Commit  %#GitLogBarDim#" .. plural(#list, "arquivo", "arquivos")
    .. "%#GitLogBar#%=%#GitLogBarAdd#+" .. add_total .. " %#GitLogBarDel#\u{2212}" .. del_total .. " "
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
    if q == nil or not M.is_open() then return end
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
  local f = st.files and st.files[vim.api.nvim_win_get_cursor(st.win.info)[1]]
  if f then require("config.git_compare").file_diff(st.root, f) end
end

-- Esc: limpa a busca; sem busca, volta para o código (o painel continua aberto)
local function escape()
  if st.filter then
    st.filter, st.commit_shown = nil, nil
    render_log()
    return render_commit(selected_commit())
  end
  local main = require("config.panels").main_win()
  if main then vim.api.nvim_set_current_win(main) end
end

-- ---------------------------------------------------------------------------
-- Menu de ações (m ou botão direito): no commit e na branch, como no PhpStorm
-- ---------------------------------------------------------------------------
local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "Git" }) end

local function after_git()
  vim.cmd("silent! checktime")
  pcall(function() require("neo-tree.sources.manager").refresh("filesystem") end)
  pcall(function() if require("config.commit").is_open() then require("config.commit").refresh() end end)
  vim.cmd("redrawstatus!")
  if M.is_open() then refresh() end
end

-- roda uma operação; se parar em conflito, abre a janela de conflitos
local function git_op(args, ok_msg, fail_msg)
  local cmd = { "git" }
  vim.list_extend(cmd, args)
  local r = vim.system(cmd, { cwd = st.root, text = true }):wait()
  local root = st.root
  after_git()
  if r.code == 0 then return notify(ok_msg) end
  if require("config.conflicts").check(root) then
    return notify(fail_msg .. ": há arquivos em conflito para resolver.", vim.log.levels.WARN)
  end
  notify(fail_msg .. ":\n" .. vim.trim((r.stdout or "") .. (r.stderr or "")), vim.log.levels.WARN)
end

local function reset_menu(c, short)
  local cur = st.current ~= "" and st.current or "HEAD"
  require("config.popup_menu").open({
    { label = "Soft: mantém as mudanças preparadas", key = "s", run = function()
      git_op({ "reset", "--soft", c.hash }, "'" .. cur .. "' agora aponta para " .. short, "Reset falhou")
    end },
    { label = "Mixed: mantém as mudanças nos arquivos", key = "m", run = function()
      git_op({ "reset", "--mixed", c.hash }, "'" .. cur .. "' agora aponta para " .. short, "Reset falhou")
    end },
    { label = "Hard: descarta as mudanças", key = "h", run = function()
      if vim.fn.confirm("Reset hard de '" .. cur .. "' para " .. short .. "?\nAs mudanças não commitadas e os commits depois dele somem da branch.",
        "&Descartar e resetar\n&Cancelar", 2, "Warning") ~= 1 then return end
      git_op({ "reset", "--hard", c.hash }, "'" .. cur .. "' agora aponta para " .. short, "Reset falhou")
    end },
  }, { title = "Reset de '" .. cur .. "' para " .. short, width = 44 })
end

local function commit_menu(opts)
  local c = selected_commit()
  if not c then return end
  local short = c.hash:sub(1, 7)
  -- em commit de merge, cherry-pick e revert usam o primeiro pai (a branch que recebeu o merge)
  local parent = c.merge and { "-m", "1" } or {}
  require("config.popup_menu").open({
    { label = "Copiar hash", key = "y", run = function()
      vim.fn.setreg("+", c.hash)
      notify("Hash copiado: " .. short)
    end },
    { label = "Nova branch a partir daqui…", key = "b", run = function() require("config.branches").new_branch(c.hash) end },
    { label = "Checkout deste commit", key = "o", run = function()
      git_op({ "checkout", c.hash }, "Checkout de " .. short .. " (sem branch; crie uma para commitar aqui)", "Checkout falhou")
    end },
    { label = "Cherry-pick", key = "p", run = function()
      git_op(vim.list_extend({ "cherry-pick" }, vim.list_extend(vim.deepcopy(parent), { c.hash })), "Cherry-pick de " .. short .. " feito", "Cherry-pick parou")
    end },
    { label = "Reverter commit", key = "v", run = function()
      git_op(vim.list_extend({ "revert", "--no-edit" }, vim.list_extend(vim.deepcopy(parent), { c.hash })), "Commit " .. short .. " revertido", "Revert parou")
    end },
    { label = "Reset da branch atual para cá…", key = "r", run = function() reset_menu(c, short) end },
  }, { title = short, width = 38, mouse = opts and opts.mouse })
end

local function tree_menu(opts)
  local it = st.tree[vim.api.nvim_win_get_cursor(st.win.tree)[1]]
  if not (it and it.kind == "ref" and it.ref ~= "--all" and it.ref ~= "HEAD") then return end
  local remote = st.remote_names[it.ref:match("^([^/]+)/") or ""] and not vim.tbl_contains(st.locals, it.ref)
  local items = require("config.branches").actions_for(it.ref, remote)
  local width = 24
  for _, x in ipairs(items) do width = math.max(width, vim.fn.strdisplaywidth(x.label) + (x.hint and #x.hint + 4 or 0) + 4) end
  require("config.popup_menu").open(items, { title = it.ref, width = math.min(width, 56), mouse = opts and opts.mouse })
end

-- botão direito: move o cursor para a linha clicada e abre o menu ali
local function right_click(win, menu)
  return function()
    local p = vim.fn.getmousepos()
    if p.winid ~= win() then return end
    vim.api.nvim_set_current_win(p.winid)
    pcall(vim.api.nvim_win_set_cursor, p.winid, { p.line, 0 })
    menu({ mouse = true })
  end
end

M.refresh = function() if M.is_open() then refresh() end end

-- cliques nos atalhos da barra do log
function _G.GitLogAction(id)
  vim.schedule(function()
    if id == 1 then search() elseif id == 2 then refresh() elseif id == 4 then commit_menu() else M.close() end
  end)
end

-- ---------------------------------------------------------------------------
-- Painel em ilhas (como o tema Islands do PhpStorm)
-- Um split embaixo, com metade da altura, serve só de fundo (canvas, mais escuro).
-- Branches, Log e Commit são janelas flutuantes em cima dele, com uma coluna de
-- respiro entre elas. No Neovide as flutuantes têm cantos arredondados.
-- ---------------------------------------------------------------------------
local ISLANDS = { "tree", "log", "info" }
local TREE_W = 30

local function style(win, opts)
  local wo = vim.wo[win]
  wo.number, wo.relativenumber, wo.signcolumn, wo.statuscolumn = false, false, "no", ""
  wo.foldcolumn, wo.foldenable, wo.list, wo.spell, wo.wrap = "0", false, false, false, false
  wo.cursorline = opts.cursorline ~= false
  wo.scrolloff, wo.sidescrolloff = 2, 0
end

-- ilha com o foco: título claro e seleção azul; nas outras a seleção fica apagada
local function paint(win, active)
  if not (win and vim.api.nvim_win_is_valid(win)) then return end
  vim.wo[win].winhighlight = "Normal:GitLogIsland,NormalNC:GitLogIsland,NormalFloat:GitLogIsland,EndOfBuffer:GitLogIsland"
    .. ",WinBar:" .. (active and "GitLogBarActive" or "GitLogBar") .. ",WinBarNC:GitLogBar"
    .. ",CursorLine:" .. (active and "GitLogSel" or "GitLogSelNC")
end

local function scratch(name)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "git_log"
  pcall(vim.api.nvim_buf_set_name, buf, "Git: " .. name)
  return buf
end

local function panel_wins()
  local out = {}
  for _, k in ipairs({ "tree", "log", "info", "canvas" }) do
    local w = st.win and st.win[k]
    if w and vim.api.nvim_win_is_valid(w) then table.insert(out, w) end
  end
  return out
end

function M.is_open()
  return #panel_wins() == 4 and vim.api.nvim_win_get_tabpage(st.win.canvas) == vim.api.nvim_get_current_tabpage()
end

function M.close()
  if st.closing then return end
  st.closing = true
  if st.group then pcall(vim.api.nvim_del_augroup_by_id, st.group) end
  local back = st.prev_win
  for _, w in ipairs(panel_wins()) do -- ilhas primeiro, o fundo por último
    if not pcall(vim.api.nvim_win_close, w, true) then
      -- era a última janela: em vez de fechar, troca para um buffer vazio
      pcall(vim.api.nvim_win_set_buf, w, vim.api.nvim_create_buf(true, false))
    end
  end
  st = {}
  if back and vim.api.nvim_win_is_valid(back) then pcall(vim.api.nvim_set_current_win, back) end
  pcall(function() require("config.activity_bar").ensure() end)
end

local function canvas_height() return math.max(12, math.floor(vim.o.lines * HEIGHT)) end

-- posição de cada ilha dentro do fundo: 1 coluna de margem e de respiro entre elas
local function geometry()
  local W = vim.api.nvim_win_get_width(st.win.canvas)
  local H = vim.api.nvim_win_get_height(st.win.canvas)
  local iw = math.max(44, math.floor(vim.o.columns * 0.28))
  local lw = W - TREE_W - iw - 4
  if lw < 50 then
    iw = math.max(30, W - TREE_W - 4 - 50)
    lw = math.max(10, W - TREE_W - iw - 4)
  end
  local cols = { tree = { 1, TREE_W }, log = { 2 + TREE_W, lw }, info = { 3 + TREE_W + lw, iw } }
  local out = {}
  for k, cw in pairs(cols) do
    out[k] = { relative = "win", win = st.win.canvas, row = 0, col = cw[1], width = cw[2], height = math.max(1, H) }
  end
  return out
end

local function place()
  if st.placing then return end
  st.placing = true
  for k, cfg in pairs(geometry()) do
    if vim.api.nvim_win_is_valid(st.win[k]) then pcall(vim.api.nvim_win_set_config, st.win[k], cfg) end
  end
  st.placing = false
end

function M.open()
  if M.is_open() then return vim.api.nvim_set_current_win(st.win.log) end
  if st.win then M.close() end -- aberto em outra aba do Neovim
  local r = vim.system({ "git", "rev-parse", "--show-toplevel" }, { cwd = vim.fn.getcwd(), text = true }):wait()
  if r.code ~= 0 then return vim.notify("Esta pasta não é um repositório git", vim.log.levels.WARN, { title = "Git" }) end

  -- mesmo lugar do Terminal, Run e Problems (embaixo): esconde eles
  for _, mod in ipairs({ "config.terminal", "config.run_panel", "config.problems" }) do
    local p = package.loaded[mod]
    if p and p.is_open() then (p.hide or p.close)() end
  end

  st = { root = vim.trim(r.stdout), ref = "--all", collapsed = {}, buf = {}, win = {}, prev_win = vim.api.nvim_get_current_win() }
  st.me = vim.trim(git({ "config", "user.name" }))
  load_branches()
  -- pastas e remotos começam recolhidos; Local aberto
  for _, n in ipairs(st.locals) do local f = n:match("^([^/]+)/"); if f then st.collapsed["local/" .. f] = true end end
  for _, n in ipairs(st.remotes) do
    local rem, folder = n:match("^([^/]+)/([^/]+)/")
    if rem then st.collapsed["remote/" .. rem .. "/" .. folder] = true end
  end

  -- fundo
  st.buf.canvas = scratch("painel")
  st.win.canvas = vim.api.nvim_open_win(st.buf.canvas, true, { split = "below", win = -1, height = canvas_height() })
  style(st.win.canvas, { cursorline = false })
  vim.wo[st.win.canvas].winfixheight = true
  vim.wo[st.win.canvas].winbar = ""
  vim.wo[st.win.canvas].winhighlight = "Normal:GitLogCanvas,NormalNC:GitLogCanvas,EndOfBuffer:GitLogCanvas"
  vim.bo[st.buf.canvas].modifiable = false
  require("config.panels").mark(st.win.canvas, st.buf.canvas)

  -- ilhas
  local geo = geometry()
  for _, k in ipairs(ISLANDS) do
    st.buf[k] = scratch(k)
    local cfg = vim.tbl_extend("force", geo[k], { style = "minimal", zindex = 5, focusable = true })
    st.win[k] = vim.api.nvim_open_win(st.buf[k], k == "log", cfg)
    style(st.win[k], {})
    paint(st.win[k], k == "log")
    require("config.panels").mark(st.win[k], st.buf[k])
  end
  vim.wo[st.win.tree].winbar = " Branches"
  vim.wo[st.win.info].winbar = " Commit"

  -- teclas
  local function map(buf, lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true }) end
  for idx, k in ipairs(ISLANDS) do
    local b = st.buf[k]
    map(b, "q", M.close)
    map(b, "<D-w>", M.close)
    map(b, "<Esc>", escape)
    map(b, "<Tab>", function() vim.api.nvim_set_current_win(st.win[ISLANDS[idx % #ISLANDS + 1]]) end)
    map(b, "<S-Tab>", function() vim.api.nvim_set_current_win(st.win[ISLANDS[(idx - 2) % #ISLANDS + 1]]) end)
    map(b, "/", search)
    map(b, "r", refresh)
  end
  map(st.buf.tree, "<CR>", function() tree_activate() end)
  map(st.buf.tree, "<LeftRelease>", function()
    local p = vim.fn.getmousepos()
    if p.winid == st.win.tree then tree_activate(p.line) end
  end)
  -- Enter no log: vai para o primeiro arquivo do commit
  map(st.buf.log, "<CR>", function()
    vim.api.nvim_set_current_win(st.win.info)
    if st.first_file then pcall(vim.api.nvim_win_set_cursor, st.win.info, { st.first_file, 0 }) end
  end)
  map(st.buf.log, "m", function() commit_menu() end)
  map(st.buf.log, "<RightMouse>", right_click(function() return st.win.log end, commit_menu))
  map(st.buf.tree, "m", function() tree_menu() end)
  map(st.buf.tree, "<RightMouse>", right_click(function() return st.win.tree end, tree_menu))
  map(st.buf.info, "<CR>", open_file)
  map(st.buf.info, "<2-LeftMouse>", require("config.panels").after_click(open_file))

  st.group = vim.api.nvim_create_augroup("git_log_panel", { clear = true })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = st.group, buffer = st.buf.log,
    callback = function() render_commit(selected_commit()) end,
  })
  vim.api.nvim_create_autocmd({ "WinEnter", "WinLeave" }, {
    group = st.group,
    callback = function(ev)
      local cur = vim.api.nvim_get_current_win()
      -- o fundo não tem conteúdo: um clique no respiro entre as ilhas cai no log
      if ev.event == "WinEnter" and cur == st.win.canvas then
        return vim.schedule(function() if M.is_open() then vim.api.nvim_set_current_win(st.win.log) end end)
      end
      for _, k in ipairs(ISLANDS) do
        if st.win[k] == cur then paint(cur, ev.event == "WinEnter") end
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = st.group,
    callback = function()
      if not M.is_open() then return end
      pcall(vim.api.nvim_win_set_height, st.win.canvas, canvas_height())
      place()
    end,
  })
  vim.api.nvim_create_autocmd("WinResized", {
    group = st.group,
    callback = function()
      if not M.is_open() or st.placing then return end
      place()
      render_tree()
      render_log()
      st.commit_shown = nil
      render_commit(selected_commit())
    end,
  })
  -- fechar o fundo ou uma das ilhas (:q, :only, Cmd+W) fecha o painel inteiro
  vim.api.nvim_create_autocmd("WinClosed", {
    group = st.group,
    callback = function(ev)
      for _, w in pairs(st.win or {}) do
        if w == tonumber(ev.match) then return vim.schedule(M.close) end
      end
    end,
  })

  select_ref("--all")
  vim.api.nvim_set_current_win(st.win.log)
  pcall(function() require("config.activity_bar").ensure() end)
end

-- Botão Git da barra lateral e atalhos: abre; se já estiver aberto, fecha
function M.toggle()
  if M.is_open() then return M.close() end
  M.open()
end

local function colors()
  local ok, c = pcall(require, "config.palette")
  if not ok then return end
  local set = vim.api.nvim_set_hl
  local bright = "#DFE1E5"
  local canvas, island = c.canvas, c.bg -- mesmo fundo e mesma ilha do resto do editor
  set(0, "GitLogCanvas", { fg = canvas, bg = canvas })
  set(0, "GitLogIsland", { fg = c.fg, bg = island })
  set(0, "GitLogBar", { fg = c.fg_dim, bg = island })
  set(0, "GitLogBarActive", { fg = bright, bg = island, bold = true })
  set(0, "GitLogBarStrong", { fg = bright, bg = island })
  set(0, "GitLogBarDim", { fg = c.fg_faint, bg = island })
  set(0, "GitLogBarAdd", { fg = c.add, bg = island })
  set(0, "GitLogBarDel", { fg = "#C9616B", bg = island })
  set(0, "GitLogKey", { fg = c.fg, bg = c.border })
  set(0, "GitLogFilter", { fg = bright, bg = c.diff_text })
  set(0, "GitLogSel", { bg = "#2E436E" })
  set(0, "GitLogSelNC", { bg = "#26282C" })
  set(0, "GitLogTreeSel", { bg = "#2A2C31" })
  set(0, "GitLogRule", { fg = "#2C2E33" })
  set(0, "GitLogAccent", { fg = c.accent })
  set(0, "GitLogArrow", { fg = c.fg_faint })
  set(0, "GitLogGroup", { fg = c.fg, bold = true })
  set(0, "GitLogFolder", { fg = c.fg })
  set(0, "GitLogCount", { fg = c.fg_faint })
  set(0, "GitLogIcon", { fg = c.fg_faint })
  set(0, "GitLogStar", { fg = "#E8B647" })
  set(0, "GitLogHead", { fg = c.hint })
  set(0, "GitLogText", { fg = c.fg })
  set(0, "GitLogCurrent", { fg = bright, bold = true })
  set(0, "GitLogRefSelected", { fg = bright, bold = true })
  set(0, "GitLogAuthor", { fg = c.fg_dim })
  set(0, "GitLogAuthorMe", { fg = c.fg })
  set(0, "GitLogDate", { fg = c.fg_faint })
  set(0, "GitLogHash", { fg = c.linenr })
  set(0, "GitLogSubject", { fg = bright })
  set(0, "GitLogMerge", { fg = c.fg_faint })
  set(0, "GitLogEmpty", { fg = c.fg_faint, italic = true })
  set(0, "GitLogTitle", { fg = bright, bold = true })
  set(0, "GitLogBody", { fg = c.fg })
  set(0, "GitLogMeta", { fg = c.fg_dim })
  set(0, "GitLogDeleted", { fg = c.fg_faint, strikethrough = true })
  -- etiquetas das refs: branch atual, local, remota, tag
  set(0, "GitLogChipHead", { fg = "#E6F4E7", bg = "#2F5A35", bold = true })
  set(0, "GitLogChipLocal", { fg = "#CFE0F7", bg = "#253A57" })
  set(0, "GitLogChipRemote", { fg = c.fg_dim, bg = c.bg_float })
  set(0, "GitLogChipTag", { fg = "#F1E2BC", bg = "#4A3F24" })
  set(0, "GitLogFileM", { fg = c.change, bold = true })
  set(0, "GitLogFileA", { fg = c.add, bold = true })
  set(0, "GitLogFileD", { fg = c.error, bold = true })
  set(0, "GitLogFileR", { fg = c.warn, bold = true })
  set(0, "GitLogDel", { fg = "#C9616B" })
  set(0, "GitLogHeadDot", { fg = c.hint })
  -- trilhas do grafo, como as linhas coloridas do PhpStorm
  local lanes = { c.variable, c.method, c.hint, c.tag, c.field, c.static }
  for i, color in ipairs(lanes) do set(0, "GitLogLane" .. i, { fg = color }) end
end
colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = colors })

return M
