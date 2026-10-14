-- Popup de branches no estilo PhpStorm (abre ao clicar na branch da barra de baixo)
local M = {}

local I = {
  search = "\u{F0349}", pull = "\u{F01DA}", commit = "\u{F0718}", push = "\u{F01D8}",
  new = "\u{F0415}", tag = "\u{F04F9}", branch = "\u{F062C}", star = "\u{F04CE}",
  folder = "\u{F024B}", down = "\u{F0140}", right = "\u{F0142}", arrow = "\u{F0142}",
}
local FAVORITES = { main = true, master = true, develop = true, dev = true }

local ns = vim.api.nvim_create_namespace("branches_popup")
local st = {}   -- estado do popup aberto

-- ---------------------------------------------------------------------------
-- git
-- ---------------------------------------------------------------------------
local function root()
  local r = vim.system({ "git", "rev-parse", "--show-toplevel" }, { cwd = vim.fn.getcwd(), text = true }):wait()
  return r.code == 0 and vim.trim(r.stdout) or nil
end

local function git_sync(args)
  local cmd = { "git" }
  vim.list_extend(cmd, args)
  return vim.system(cmd, { cwd = st.root or vim.fn.getcwd(), text = true }):wait()
end

local function git(args, cb)
  local cmd = { "git" }
  vim.list_extend(cmd, args)
  vim.system(cmd, { cwd = st.root or vim.fn.getcwd(), text = true }, function(r) vim.schedule(function() cb(r) end) end)
end

local function lines(out) return vim.split(vim.trim(out or ""), "\n", { trimempty = true }) end

local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "Git" }) end

local function after_change()
  vim.cmd("silent! checktime")
  pcall(function() require("neo-tree.sources.manager").refresh("filesystem") end)
  pcall(function() if require("config.commit").is_open() then require("config.commit").refresh() end end)
  pcall(function()
    local gl = package.loaded["config.git_log"]
    if gl and gl.is_open() then gl.refresh() end
  end)
  vim.cmd("redrawstatus!")
end

local function load()
  local current = vim.trim(git_sync({ "branch", "--show-current" }).stdout or "")
  local locals, upstream = {}, {}
  for _, l in ipairs(lines(git_sync({ "for-each-ref", "--format=%(refname:short)\t%(upstream:short)", "refs/heads" }).stdout)) do
    local name, up = l:match("^([^\t]+)\t?(.*)$")
    if name then table.insert(locals, name); upstream[name] = up ~= "" and up or nil end
  end
  local remotes = {}
  for _, l in ipairs(lines(git_sync({ "for-each-ref", "--format=%(refname:short)", "refs/remotes" }).stdout)) do
    if not l:match("/HEAD$") and l:find("/") then table.insert(remotes, l) end
  end
  -- recentes: ordem dos checkouts no reflog
  local recent, seen = {}, {}
  local is_local = {}
  for _, b in ipairs(locals) do is_local[b] = true end
  for _, l in ipairs(lines(git_sync({ "reflog", "--format=%gs", "-n", "300" }).stdout)) do
    local to = l:match("^checkout: moving from .- to (.+)$")
    if to and is_local[to] and not seen[to] then
      seen[to] = true
      table.insert(recent, to)
      if #recent >= 6 then break end
    end
  end
  return { current = current, locals = locals, remotes = remotes, recent = recent, upstream = upstream }
end

-- ---------------------------------------------------------------------------
-- Ações
-- ---------------------------------------------------------------------------
local function close()
  -- (por chave, não ipairs: sem submenu o sub_win é nil e o ipairs parava antes de fechar as outras)
  for _, key in ipairs({ "sub_win", "input_win", "list_win" }) do
    local w = st[key]
    if w and vim.api.nvim_win_is_valid(w) then pcall(vim.api.nvim_win_close, w, true) end
  end
  vim.cmd.stopinsert()
  if st.prev_win and vim.api.nvim_win_is_valid(st.prev_win) then pcall(vim.api.nvim_set_current_win, st.prev_win) end
  st = {}
end
M.close = close

local function local_name(remote_ref)
  return remote_ref:gsub("^[^/]+/", "", 1)
end

function M.checkout(name, is_remote)
  local target = is_remote and local_name(name) or name
  local function done(r)
    if r.code == 0 then
      notify("Branch: " .. target)
      return after_change()
    end
    local err = (r.stderr or "") .. (r.stdout or "")
    if err:match("would be overwritten") or err:match("commit your changes") then
      local ok = vim.fn.confirm("Há alterações que impedem a troca para '" .. target .. "'.\n"
        .. "Guardar as alterações (stash), trocar de branch e trazê-las de volta?", "&Smart checkout\n&Cancelar", 1, "Question")
      if ok ~= 1 then return end
      git({ "stash", "push", "-u", "-m", "smart checkout -> " .. target }, function(s)
        if s.code ~= 0 then return notify("Stash falhou:\n" .. (s.stderr or ""), vim.log.levels.ERROR) end
        git({ "switch", target }, function(r2)
          if r2.code ~= 0 then
            git({ "stash", "pop" }, function() end)
            return notify("Troca falhou:\n" .. (r2.stderr or ""), vim.log.levels.ERROR)
          end
          git({ "stash", "pop" }, function(p)
            if p.code ~= 0 then
              notify("Trocou para " .. target .. ", mas houve conflito ao trazer as alterações de volta.\n"
                .. "Elas continuam guardadas no stash.", vim.log.levels.WARN)
            else
              notify("Branch: " .. target .. " (alterações mantidas)")
            end
            after_change()
          end)
        end)
      end)
      return
    end
    notify("Troca de branch falhou:\n" .. err, vim.log.levels.ERROR)
  end
  -- branch remota sem local: o git switch cria a local acompanhando a remota
  git({ "switch", target }, done)
end

local function create_branch(name, from)
  local args = { "switch", "-c", name }
  if from then table.insert(args, from) end
  git(args, function(r)
    if r.code == 0 then
      notify("Nova branch: " .. name .. (from and ("  (a partir de " .. from .. ")") or ""))
      after_change()
    else
      notify("Não foi possível criar a branch:\n" .. (r.stderr or ""), vim.log.levels.ERROR)
    end
  end)
end

local function ask_name(from)
  vim.ui.input({ prompt = "Nova branch a partir de " .. from .. ": " }, function(name)
    if not name or vim.trim(name) == "" then return end
    create_branch(vim.trim(name), from)
  end)
end

-- Nova branch: escolhe a origem (a partir de qual branch) e depois o nome
function M.new_branch(from)
  st.root = st.root or root()
  if from then return ask_name(from) end
  -- atualiza as branches do remoto em segundo plano enquanto você escolhe
  git({ "fetch", "--quiet", "--prune" }, function() end)
  local d = load()
  local items, seen = {}, {}
  local function add(name, kind)
    if not name or name == "" or seen[name] then return end
    seen[name] = true
    table.insert(items, { name = name, kind = kind })
  end
  add(d.current, "atual")
  for _, fav in ipairs({ "main", "master", "develop", "dev" }) do
    for _, b in ipairs(d.locals) do if b == fav then add(b, "local") end end
  end
  for _, b in ipairs(d.recent) do add(b, "local") end
  for _, b in ipairs(d.locals) do add(b, "local") end
  for _, b in ipairs(d.remotes) do add(b, "remota") end
  vim.ui.select(items, {
    prompt = "Nova branch a partir de",
    format_item = function(it)
      local tag = it.kind == "atual" and "  (atual)" or (it.kind == "remota" and "  (remota)" or "")
      return it.name .. tag
    end,
  }, function(choice)
    if not choice then return end
    vim.defer_fn(function() ask_name(choice.name) end, 60)
  end)
end

function M.update_project()
  notify("Atualizando (git pull)…")
  git({ "pull", "--no-edit" }, function(r)
    if r.code == 0 then notify("Projeto atualizado\n" .. vim.trim(r.stdout or "")); after_change()
    else notify("git pull falhou:\n" .. (r.stderr or ""), vim.log.levels.ERROR) end
  end)
end

local function checkout_revision()
  vim.ui.input({ prompt = "Tag ou revisão: " }, function(rev)
    if not rev or vim.trim(rev) == "" then return end
    git({ "checkout", vim.trim(rev) }, function(r)
      if r.code == 0 then notify("Checkout: " .. vim.trim(rev)); after_change()
      else notify("Checkout falhou:\n" .. (r.stderr or ""), vim.log.levels.ERROR) end
    end)
  end)
end

-- ---------------------------------------------------------------------------
-- Ações de uma branch (usadas pelo submenu)
-- ---------------------------------------------------------------------------
local function git_report(args, ok_msg, fail_msg)
  local repo = st.root or root()
  git(args, function(r)
    if r.code == 0 then notify(ok_msg); after_change(); return end
    after_change()
    -- parou em conflito: abre a janela de conflitos em vez de só mostrar o erro
    if require("config.conflicts").check(repo) then
      return notify(fail_msg .. ": há arquivos em conflito para resolver.", vim.log.levels.WARN)
    end
    notify(fail_msg .. ":\n" .. vim.trim((r.stdout or "") .. (r.stderr or "")))
  end)
end

-- remoto e nome da branch remota que uma branch local acompanha (origin, feat/x)
local function tracked(name)
  local up = st.data and st.data.upstream[name]
  if not up then return nil end
  return up:match("^([^/]+)/"), local_name(up), up
end

-- Abre o resultado de um comando git numa aba nova, só leitura (q fecha)
local function show_output(title, args, ft)
  local r = git_sync(args)
  local out = vim.split((r.stdout or "") .. (r.stderr or ""), "\n", { plain = true })
  if #out == 1 and out[1] == "" then out = { "Nenhuma diferença." } end
  vim.cmd("tabnew")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
  vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].modifiable = "nofile", "wipe", false
  vim.bo[buf].filetype = ft or "diff"
  pcall(vim.api.nvim_buf_set_name, buf, title)
  vim.t.no_activity_bar = true
  require("config.git_compare").own_tab()
end

local A = {}

function A.diff_working_tree(name, repo)
  require("config.git_compare").working_tree(repo or st.root or root(), name)
end

-- Commits que uma tem e a outra não, nos dois sentidos (janela no estilo do PhpStorm)
function A.compare(name, cur, repo)
  require("config.git_compare").open(repo or st.root or root(), name, cur)
end

function A.new_worktree(name)
  vim.ui.input({ prompt = "Nova branch no worktree (a partir de " .. name .. "): " }, function(branch)
    branch = branch and vim.trim(branch) or ""
    if branch == "" then return end
    local repo = vim.fn.fnamemodify(st.root or root(), ":t")
    local default = vim.fn.fnamemodify((st.root or root()) .. "/..", ":p") .. repo .. "-" .. branch:gsub("[/%s]", "-")
    vim.defer_fn(function()
      vim.ui.input({ prompt = "Pasta do worktree: ", default = default }, function(path)
        path = path and vim.trim(path) or ""
        if path == "" then return end
        git_report({ "worktree", "add", "-b", branch, path, name }, "Worktree criado em " .. path, "Não foi possível criar o worktree")
      end)
    end, 60)
  end)
end

function A.update(name, cur)
  if name == cur then return M.update_project() end
  local remote, rbranch = tracked(name)
  if not remote then return notify("'" .. name .. "' não acompanha nenhuma branch remota", vim.log.levels.WARN) end
  notify("Atualizando " .. name .. "…")
  git_report({ "fetch", remote, rbranch .. ":" .. name }, "Atualizada: " .. name, "Não foi possível atualizar '" .. name .. "'")
end

function A.push(name, cur)
  if name == cur then return require("config.commit").push() end
  local remote, rbranch = tracked(name)
  notify("Push de " .. name .. "…")
  if remote then
    git_report({ "push", remote, name .. ":" .. rbranch }, "Push feito: " .. name, "Push falhou")
  else
    git_report({ "push", "-u", "origin", name }, "Push feito: " .. name .. " (agora acompanha origin/" .. name .. ")", "Push falhou")
  end
end

function A.tracked_branch(name)
  local remotes = st.data and st.data.remotes or {}
  local _, _, up = tracked(name)
  local items = vim.deepcopy(remotes)
  table.insert(items, "(nenhuma)")
  vim.ui.select(items, {
    prompt = "Branch remota que '" .. name .. "' acompanha",
    format_item = function(r) return r == up and (r .. "  (atual)") or r end,
  }, function(choice)
    if not choice or choice == up then return end
    if choice == "(nenhuma)" then
      return git_report({ "branch", "--unset-upstream", name }, "'" .. name .. "' não acompanha mais nenhuma remota", "Falhou")
    end
    git_report({ "branch", "--set-upstream-to=" .. choice, name }, "'" .. name .. "' agora acompanha " .. choice, "Falhou")
  end)
end

function A.rename(name)
  vim.ui.input({ prompt = "Novo nome para '" .. name .. "': ", default = name }, function(new)
    new = new and vim.trim(new) or ""
    if new == "" or new == name then return end
    git_report({ "branch", "-m", name, new }, "Branch renomeada: " .. new, "Não foi possível renomear")
  end)
end

function A.delete(name, remote)
  if remote then
    local r, b = name:match("^([^/]+)/(.+)$")
    if vim.fn.confirm("Apagar a branch remota '" .. name .. "'?\nIsso apaga a branch no servidor (" .. r .. ") para todo mundo.",
      "&Apagar\n&Cancelar", 2, "Warning") ~= 1 then return end
    return git_report({ "push", r, "--delete", b }, "Branch remota apagada: " .. name, "Não foi possível apagar")
  end
  if vim.fn.confirm("Apagar a branch '" .. name .. "'?", "&Apagar\n&Cancelar", 2, "Question") ~= 1 then return end
  git({ "branch", "-d", name }, function(r)
    if r.code == 0 then return notify("Branch apagada: " .. name) end
    if (r.stderr or ""):match("not fully merged") and
      vim.fn.confirm("'" .. name .. "' tem commits que não estão em outra branch. Apagar mesmo assim?", "&Apagar\n&Cancelar", 2, "Warning") == 1 then
      git_report({ "branch", "-D", name }, "Branch apagada: " .. name, "Não foi possível apagar")
    else
      notify(r.stderr or "", vim.log.levels.ERROR)
    end
  end)
end

-- Itens do submenu, como no PhpStorm (mudam para a branch atual, outra local ou remota)
local function branch_actions(item)
  local name, remote = item.name, item.remote
  local cur = st.data and st.data.current or ""
  local is_cur = not remote and name == cur
  local _, _, up = tracked(name)
  local repo = st.root -- o popup fecha antes de a ação rodar
  local it = {}
  local function add(label, run, hint) table.insert(it, { label = label, run = run, hint = hint }) end
  local function sep() table.insert(it, { sep = true }) end

  if not is_cur then add("Checkout", function() M.checkout(name, remote) end) end
  add("New Branch from '" .. name .. "'…", function() M.new_branch(name) end, is_cur and "⌥⌘N" or nil)
  if not is_cur and not remote and cur ~= "" then
    add("Checkout and Rebase onto '" .. cur .. "'", function()
      git_report({ "rebase", cur, name }, "'" .. name .. "' rebaseada em '" .. cur .. "'", "Rebase parou")
    end)
  end
  sep()
  if not is_cur and cur ~= "" then add("Compare with '" .. cur .. "'", function() A.compare(name, cur, repo) end) end
  add("Show Diff with Working Tree", function() A.diff_working_tree(name, repo) end)
  if not remote then add("New Worktree from '" .. name .. "'…", function() A.new_worktree(name) end) end
  if not is_cur and cur ~= "" then
    sep()
    add("Rebase '" .. cur .. "' onto '" .. name .. "'", function() git_report({ "rebase", name }, "Rebase feito", "Rebase parou") end)
    add("Merge '" .. name .. "' into '" .. cur .. "'", function() git_report({ "merge", "--no-edit", name }, "Merge feito", "Merge com problemas") end)
  end
  if not remote then
    sep()
    add("Update", function() A.update(name, cur) end)
    add("Push…", function() A.push(name, cur) end, is_cur and "⇧⌘K" or nil)
    add("Tracked Branch " .. (up and ("'" .. up .. "'") or "(nenhuma)") .. "…", function() A.tracked_branch(name) end)
  end
  sep()
  if not remote then add("Rename…", function() A.rename(name) end) end
  if not is_cur then add("Delete", function() A.delete(name, remote) end) end
  -- sem separador sobrando no fim
  while it[#it] and it[#it].sep do table.remove(it) end
  return it
end

--- Ações de uma branch fora do popup (menu da árvore de branches na janela de Git)
function M.actions_for(name, remote)
  st.root = root()
  st.data = load()
  return vim.tbl_filter(function(it) return not it.sep end, branch_actions({ name = name, remote = remote }))
end

-- ---------------------------------------------------------------------------
-- Submenu ao lado da lista (o popup de branches continua aberto)
-- ---------------------------------------------------------------------------
local sub_ns = vim.api.nvim_create_namespace("branches_submenu")

local function close_sub(back)
  if st.sub_win and vim.api.nvim_win_is_valid(st.sub_win) then pcall(vim.api.nvim_win_close, st.sub_win, true) end
  st.sub_win, st.sub = nil, nil
  if back and st.input_win and vim.api.nvim_win_is_valid(st.input_win) then
    vim.api.nvim_set_current_win(st.input_win)
    vim.cmd.startinsert({ bang = true })
  end
end

local function sub_select(i, dir)
  local s = st.sub
  if not s then return end
  i = math.max(1, math.min(i, #s.items))
  while s.items[i] and s.items[i].sep do i = i + (dir or 1) end
  if not s.items[i] then return end
  s.sel = i
  pcall(vim.api.nvim_win_set_cursor, st.sub_win, { i, 0 })
end

local function sub_activate(i)
  local s = st.sub
  local it = s and s.items[i or s.sel]
  if not it or it.sep then return end
  close()
  vim.defer_fn(it.run, 80)
end

local function branch_menu(item, line)
  close_sub()
  local items = branch_actions(item)
  local width = 20
  for _, it in ipairs(items) do
    if not it.sep then width = math.max(width, vim.fn.strdisplaywidth(it.label) + (it.hint and vim.fn.strdisplaywidth(it.hint) + 4 or 0) + 4) end
  end
  width = math.min(width, math.max(30, st.width - 4))
  local text, marks = {}, {}
  for i, it in ipairs(items) do
    if it.sep then
      table.insert(text, " " .. string.rep("\u{2500}", width - 2))
      table.insert(marks, { i - 1, 0, -1, "BranchesSep" })
    else
      local label = it.label
      local room = width - 3 - (it.hint and vim.fn.strdisplaywidth(it.hint) + 2 or 0)
      if vim.fn.strdisplaywidth(label) > room then label = vim.fn.strcharpart(label, 0, room - 1) .. "…" end
      local left = "  " .. label
      local hint = it.hint or ""
      local l = left .. string.rep(" ", math.max(1, width - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(hint) - 1)) .. hint
      table.insert(text, l)
      if it.hint then table.insert(marks, { i - 1, #l - #hint, -1, "BranchesHint" }) end
    end
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
  vim.bo[buf].modifiable = false
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(buf, sub_ns, m[1], m[2], { end_col = m[3] == -1 and #text[m[1] + 1] or m[3], hl_group = m[4] })
  end
  -- à esquerda da lista (o popup fica encostado na direita), na altura da branch escolhida
  local pos = vim.api.nvim_win_get_position(st.list_win)
  local first_visible = vim.api.nvim_win_call(st.list_win, function() return vim.fn.line("w0") end)
  local row = pos[1] + (line or st.sel or 1) - first_visible
  row = math.max(1, math.min(row, vim.o.lines - #text - 4))
  local col = math.max(0, pos[2] - width - 3)
  st.sub_win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", row = row, col = col, width = width, height = #text,
    style = "minimal", border = "rounded", zindex = 220,
  })
  vim.wo[st.sub_win].cursorline = true
  vim.wo[st.sub_win].winhighlight = "Normal:BranchesNormal,FloatBorder:BranchesBorder,CursorLine:BranchesSel"
  st.sub = { items = items, sel = 1 }
  vim.cmd.stopinsert()
  sub_select(1, 1)

  local function map(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true }) end
  for _, k in ipairs({ "j", "<Down>", "<C-n>", "<C-j>" }) do map(k, function() sub_select(st.sub.sel + 1, 1) end) end
  for _, k in ipairs({ "k", "<Up>", "<C-p>", "<C-k>" }) do map(k, function() sub_select(st.sub.sel - 1, -1) end) end
  for _, k in ipairs({ "<CR>", "l", "<Right>" }) do map(k, function() sub_activate() end) end
  for _, k in ipairs({ "<Esc>", "h", "<Left>" }) do map(k, function() close_sub(true) end) end
  map("q", close)
  map("<LeftRelease>", function()
    local p = vim.fn.getmousepos()
    if p.winid == st.sub_win then sub_activate(p.line) end
  end)
  -- clicar fora do submenu (e fora do popup) fecha tudo
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(function()
        local w = vim.api.nvim_get_current_win()
        if w ~= st.input_win and w ~= st.list_win and w ~= st.sub_win then close() end
      end)
    end,
  })
end

-- ---------------------------------------------------------------------------
-- Lista (árvore com Recent / Local / Remote)
-- ---------------------------------------------------------------------------
local function group_tree(names, opts)
  -- agrupa "pasta/nome" por pasta (primeiro segmento)
  local out, folders, order = {}, {}, {}
  for _, n in ipairs(names) do
    local shown = opts.strip and local_name(n) or n
    local folder, rest = shown:match("^([^/]+)/(.+)$")
    if folder then
      if not folders[folder] then folders[folder] = {}; table.insert(order, { folder = folder }) end
      table.insert(folders[folder], { name = n, label = rest })
    else
      table.insert(order, { name = n, label = shown })
    end
  end
  for _, o in ipairs(order) do
    if o.folder then
      table.insert(out, { kind = "folder", label = o.folder, level = opts.level })
      for _, b in ipairs(folders[o.folder]) do
        table.insert(out, { kind = "branch", name = b.name, label = b.label, level = opts.level + 1, remote = opts.remote })
      end
    else
      table.insert(out, { kind = "branch", name = o.name, label = o.label, level = opts.level, remote = opts.remote })
    end
  end
  return out
end

local function build_items(query)
  local d = st.data
  local items = {}
  local actions = {
    { kind = "action", icon = I.pull, label = "Update Project…", run = M.update_project },
    { kind = "action", icon = I.push, label = "Push…", hint = "⇧⌘K", run = function() require("config.commit").push() end },
    { kind = "sep" },
    { kind = "action", icon = I.new, label = "New Branch…", hint = "⌥⌘N", run = function() M.new_branch() end },
    { kind = "action", icon = "", label = "Checkout Tag or Revision…", run = checkout_revision },
    { kind = "sep" },
  }
  query = vim.trim(query or ""):lower()
  if query ~= "" then
    for _, a in ipairs(actions) do
      if a.kind == "action" and a.label:lower():find(query, 1, true) then table.insert(items, a) end
    end
    local seen = {}
    for _, list in ipairs({ { d.locals, false }, { d.remotes, true } }) do
      for _, n in ipairs(list[1]) do
        if n:lower():find(query, 1, true) and not seen[n] then
          seen[n] = true
          table.insert(items, { kind = "branch", name = n, label = n, level = 0, remote = list[2] })
        end
      end
    end
    return items
  end
  vim.list_extend(items, actions)
  local sections = {
    { id = "recent", label = "Recent", names = d.recent, remote = false },
    { id = "local", label = "Local", names = d.locals, remote = false },
    { id = "remote", label = "Remote", names = d.remotes, remote = true },
  }
  for _, s in ipairs(sections) do
    if #s.names > 0 then
      local collapsed = st.collapsed[s.id]
      table.insert(items, { kind = "header", id = s.id, label = s.label, level = 0, collapsed = collapsed })
      if not collapsed then
        if s.remote then
          -- agrupa por remoto (origin) e depois por pasta
          local by_remote, order = {}, {}
          for _, n in ipairs(s.names) do
            local r = n:match("^([^/]+)/")
            if not by_remote[r] then by_remote[r] = {}; table.insert(order, r) end
            table.insert(by_remote[r], n)
          end
          for _, r in ipairs(order) do
            table.insert(items, { kind = "folder", label = r, level = 1 })
            vim.list_extend(items, group_tree(by_remote[r], { level = 2, remote = true, strip = true }))
          end
        else
          vim.list_extend(items, group_tree(s.names, { level = 1, remote = false }))
        end
      end
    end
  end
  return items
end

local function selectable(it) return it and (it.kind == "action" or it.kind == "branch" or it.kind == "header") end

local function render()
  if not (st.list_buf and vim.api.nvim_buf_is_valid(st.list_buf)) then return end
  local query = st.input_buf and vim.api.nvim_buf_get_lines(st.input_buf, 0, 1, false)[1] or ""
  st.items = build_items(query)
  local text, marks = {}, {}
  local width = st.width - 2
  for i, it in ipairs(st.items) do
    local line, hls = "", {}
    local indent = string.rep("  ", it.level or 0)
    if it.kind == "sep" then
      line = " " .. string.rep("\u{2500}", width - 2)
      table.insert(hls, { 0, -1, "BranchesSep" })
    elseif it.kind == "action" then
      local left = " " .. (it.icon ~= "" and it.icon or " ") .. "  " .. it.label
      local right = it.hint or ""
      line = left .. string.rep(" ", math.max(1, width - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(right) - 1)) .. right
      table.insert(hls, { #left, -1, "BranchesHint" })
    elseif it.kind == "header" then
      line = " " .. indent .. (it.collapsed and I.right or I.down) .. " " .. it.label
      table.insert(hls, { 0, -1, "BranchesHeader" })
    elseif it.kind == "folder" then
      line = " " .. indent .. I.down .. " " .. I.folder .. " " .. it.label
      table.insert(hls, { 0, -1, "BranchesFolder" })
    else
      local is_cur = not it.remote and it.name == st.data.current
      local short = it.remote and local_name(it.name) or it.name
      local fav = FAVORITES[short] or FAVORITES[it.label]
      local icon = is_cur and I.tag or (fav and I.star or I.branch)
      local left = " " .. indent .. "  " .. icon .. " " .. it.label
      -- branch remota que esta acompanha: só mostra se o nome for diferente
      local up = (not it.remote) and st.data.upstream[it.name] or nil
      if up and local_name(up) == it.name then up = nil end
      local arrow_w = vim.fn.strdisplaywidth(I.arrow) + 1
      local leftw = vim.fn.strdisplaywidth(left)
      local free = width - leftw - arrow_w - 2
      local right = I.arrow
      if up and free >= 8 then
        if vim.fn.strdisplaywidth(up) > free then up = "…" .. vim.fn.strcharpart(up, vim.fn.strchars(up) - free + 1) end
        right = up .. " " .. I.arrow
      end
      local maxleft = width - vim.fn.strdisplaywidth(right) - 2
      if leftw > maxleft then left = vim.fn.strcharpart(left, 0, math.max(8, maxleft - 1)) .. "…" end
      line = left .. string.rep(" ", math.max(1, width - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(right) - 1)) .. right
      local icon_start = #(" " .. indent .. "  ")
      table.insert(hls, { icon_start, icon_start + #icon, is_cur and "BranchesCurrent" or (fav and "BranchesFav" or "BranchesIcon") })
      table.insert(hls, { #left, -1, "BranchesHint" })
      if is_cur then table.insert(hls, { icon_start + #icon, #left, "BranchesCurrentName" }) end
    end
    table.insert(text, line)
    for _, h in ipairs(hls) do table.insert(marks, { i - 1, h[1], h[2], h[3] }) end
  end
  if #text == 0 then text = { "  Nada encontrado" } end
  vim.bo[st.list_buf].modifiable = true
  vim.api.nvim_buf_set_lines(st.list_buf, 0, -1, false, text)
  vim.bo[st.list_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(st.list_buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    local len = #text[m[1] + 1]
    local e = m[3] == -1 and len or math.min(m[3], len)
    if m[2] < e then vim.api.nvim_buf_set_extmark(st.list_buf, ns, m[1], m[2], { end_col = e, hl_group = m[4] }) end
  end
  -- altura acompanha o conteúdo
  if st.list_win and vim.api.nvim_win_is_valid(st.list_win) then
    local h = math.max(1, math.min(#text, st.max_height))
    vim.api.nvim_win_set_height(st.list_win, h)
    M.select(st.sel or 1, 1)
  end
end

-- move a seleção para o próximo item selecionável
function M.select(i, dir)
  if not st.items or #st.items == 0 then return end
  i = math.max(1, math.min(i, #st.items))
  local tries = 0
  while not selectable(st.items[i]) and tries < #st.items do
    i = i + (dir or 1)
    if i > #st.items then i = 1 elseif i < 1 then i = #st.items end
    tries = tries + 1
  end
  st.sel = i
  if st.list_win and vim.api.nvim_win_is_valid(st.list_win) then
    pcall(vim.api.nvim_win_set_cursor, st.list_win, { i, 0 })
  end
end

local function activate(i, submenu)
  local it = st.items and st.items[i or st.sel]
  if not it then return end
  if it.kind == "header" then
    st.collapsed[it.id] = not st.collapsed[it.id]
    return render()
  elseif it.kind == "action" then
    close()
    -- espera o popup fechar e o "sair da digitação" acontecer; senão ele cancelava
    -- a caixinha de texto que a ação abre (ex.: nome da nova branch)
    return vim.defer_fn(it.run, 80)
  elseif it.kind == "branch" then
    -- como no PhpStorm: escolher a branch abre o submenu dela (Checkout é uma das opções)
    st.sel = i or st.sel
    return branch_menu(it, st.sel)
  end
end

-- ---------------------------------------------------------------------------
-- Abrir o popup (acima da barra de status, no canto direito)
-- ---------------------------------------------------------------------------
function M.open()
  if st.input_win and vim.api.nvim_win_is_valid(st.input_win) then return close() end
  local r = root()
  if not r then return notify("Não é um repositório git", vim.log.levels.WARN) end
  st = { root = r, collapsed = {}, prev_win = vim.api.nvim_get_current_win() }
  st.data = load()
  st.width = math.min(64, vim.o.columns - 6)
  st.max_height = math.max(8, math.floor(vim.o.lines * 0.5)) -- no máximo metade da tela

  -- lista primeiro (embaixo), campo de busca em cima dela
  local col = vim.o.columns - st.width - 2
  local bottom = vim.o.lines - vim.o.cmdheight - 2
  st.list_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[st.list_buf].bufhidden = "wipe"
  st.list_win = vim.api.nvim_open_win(st.list_buf, false, {
    relative = "editor", anchor = "SW", row = bottom, col = col, width = st.width, height = st.max_height,
    style = "minimal", border = { "├", "─", "┤", "│", "╯", "─", "╰", "│" }, zindex = 210,
  })
  vim.wo[st.list_win].cursorline = true
  vim.wo[st.list_win].winhighlight = "Normal:BranchesNormal,FloatBorder:BranchesBorder,CursorLine:BranchesSel"

  st.input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[st.input_buf].bufhidden = "wipe"
  vim.b[st.input_buf].completion = false -- sem a lista de completar código no campo de busca
  st.input_win = vim.api.nvim_open_win(st.input_buf, true, {
    relative = "win", win = st.list_win, anchor = "SW", row = -1, col = -1, width = st.width, height = 1,
    style = "minimal", border = { "╭", "─", "╮", "│", "", "", "", "│" }, zindex = 211,
  })
  vim.wo[st.input_win].winhighlight = "Normal:BranchesNormal,FloatBorder:BranchesBorder"
  -- lupa à esquerda do texto digitado
  local ins = vim.api.nvim_create_namespace("branches_search_icon")
  vim.api.nvim_buf_set_extmark(st.input_buf, ins, 0, 0, {
    virt_text = { { " " .. I.search .. "  ", "BranchesHint" } }, virt_text_pos = "inline", right_gravity = false,
  })

  local function placeholder()
    vim.api.nvim_buf_clear_namespace(st.input_buf, ns, 0, -1)
    if (vim.api.nvim_buf_get_lines(st.input_buf, 0, 1, false)[1] or "") == "" then
      vim.api.nvim_buf_set_extmark(st.input_buf, ns, 0, 0, { virt_text = { { "Search for branches and actions", "BranchesHint" } }, virt_text_pos = "overlay" })
    end
  end
  placeholder()
  local ibuf = st.input_buf
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = ibuf,
    callback = function() if st.input_buf then placeholder(); st.sel = 1; render() end end,
  })
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = ibuf,
    callback = function()
      vim.schedule(function()
        -- clicar na lista não fecha; clicar fora fecha
        local w = vim.api.nvim_get_current_win()
        if st.list_win and w ~= st.list_win and w ~= st.input_win and w ~= st.sub_win then close() end
      end)
    end,
  })

  local function imap(lhs, fn) vim.keymap.set({ "i", "n" }, lhs, fn, { buffer = ibuf, nowait = true }) end
  imap("<Down>", function() M.select((st.sel or 1) + 1, 1) end)
  imap("<Up>", function() M.select((st.sel or 1) - 1, -1) end)
  imap("<C-n>", function() M.select((st.sel or 1) + 1, 1) end)
  imap("<C-p>", function() M.select((st.sel or 1) - 1, -1) end)
  imap("<C-j>", function() M.select((st.sel or 1) + 1, 1) end)
  imap("<C-k>", function() M.select((st.sel or 1) - 1, -1) end)
  imap("<CR>", function() activate() end)
  imap("<Tab>", function() activate(nil, true) end)
  imap("<Esc>", close)
  vim.keymap.set("n", "q", close, { buffer = ibuf })
  -- → abre as ações da branch quando o cursor está no fim da busca
  vim.keymap.set("i", "<Right>", function()
    local line = vim.api.nvim_get_current_line()
    if vim.fn.col(".") > #line then activate(nil, true) else vim.api.nvim_feedkeys(vim.keycode("<Right>"), "n", false) end
  end, { buffer = ibuf })

  -- mouse na lista: clique escolhe; clique na seta › ou botão direito abre as ações
  local lbuf = st.list_buf
  -- (o popup abre no modo de digitação por causa da busca; o clique precisa valer nos dois modos)
  -- (arrastar não vira seleção; se a lista estiver em modo visual, o clique e Esc/q valem igual)
  vim.keymap.set({ "n", "x", "i" }, "<LeftDrag>", "<Nop>", { buffer = lbuf })
  for _, k in ipairs({ "<Esc>", "q" }) do vim.keymap.set("x", k, close, { buffer = lbuf }) end
  local function list_click()
    if vim.fn.mode():match("[vV\22]") then vim.cmd("normal! \27") end
    local pos = vim.fn.getmousepos()
    if pos.winid ~= st.list_win then return end
    local it = st.items[pos.line]
    local on_arrow = pos.wincol >= st.width - 2
    st.sel = pos.line
    if it and it.kind == "branch" and on_arrow then return activate(pos.line, true) end
    activate(pos.line)
  end
  vim.keymap.set({ "n", "i", "x" }, "<LeftRelease>", list_click, { buffer = lbuf })
  -- o clique também é tratado pelo campo de busca: a lista nunca fica com o foco (abaixo)
  vim.keymap.set({ "n", "i", "x" }, "<LeftRelease>", list_click, { buffer = ibuf })
  vim.keymap.set({ "n", "x", "i" }, "<LeftDrag>", "<Nop>", { buffer = ibuf })
  -- A lista nunca fica com o foco (como no PhpStorm): se cair nela (clique, arrasto, Ctrl-w),
  -- volta para a busca no modo de digitação. Sem isso, um arrasto deixava a lista em modo
  -- visual e o popup parecia travado.
  vim.api.nvim_create_autocmd("WinEnter", {
    buffer = lbuf,
    callback = function()
      vim.schedule(function()
        if st.list_win and vim.api.nvim_get_current_win() == st.list_win and st.input_win
          and vim.api.nvim_win_is_valid(st.input_win) then
          if vim.fn.mode():match("[vV\22]") then vim.cmd("normal! \27") end
          vim.api.nvim_set_current_win(st.input_win)
          vim.cmd.startinsert({ bang = true })
        end
      end)
    end,
  })
  vim.keymap.set({ "n", "i" }, "<RightMouse>", function()
    local pos = vim.fn.getmousepos()
    if pos.winid == st.list_win then activate(pos.line, true) end
  end, { buffer = lbuf })
  for _, k in ipairs({ "<Esc>", "q" }) do vim.keymap.set("n", k, close, { buffer = lbuf }) end
  vim.keymap.set("n", "<CR>", function() activate(vim.api.nvim_win_get_cursor(0)[1]) end, { buffer = lbuf })

  st.sel = 1
  render()
  -- começa na branch atual
  for i, it in ipairs(st.items) do
    if it.kind == "branch" and not it.remote and it.name == st.data.current then M.select(i); break end
  end
  vim.cmd.startinsert()
end

-- Cores
local function colors()
  local ok, c = pcall(require, "config.palette")
  if not ok then return end
  local set = vim.api.nvim_set_hl
  set(0, "BranchesNormal", { fg = c.fg, bg = c.bg_float })
  set(0, "BranchesBorder", { fg = c.border, bg = c.bg_float })
  set(0, "BranchesSel", { bg = "#2E436E" })
  set(0, "BranchesHint", { fg = c.fg_faint })
  set(0, "BranchesSep", { fg = c.border })
  set(0, "BranchesHeader", { fg = c.fg, bold = true })
  set(0, "BranchesFolder", { fg = c.fg })
  set(0, "BranchesIcon", { fg = c.fg_dim })
  set(0, "BranchesFav", { fg = "#E8B647" })
  set(0, "BranchesCurrent", { fg = "#E8B647" })
  set(0, "BranchesCurrentName", { fg = c.fg, bold = true })
end
colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = colors })

return M
