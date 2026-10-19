-- Contas do Git: credenciais por servidor (github.com, um GitLab da empresa…) e, se quiser,
-- uma identidade de commit (nome/e-mail) só para os projetos daquele servidor.
--   github.com                        bellinivitor   ✓ no Chaves   global            17 projetos
--   gitlab.empresa.com.br             —              ✗ falta       —                  7 projetos
-- O token/senha é digitado oculto e vai direto para o Chaves do macOS pelo próprio git
-- (git credential approve → osxkeychain); não é gravado em arquivo nenhum.
-- Enter configura · t testa a conexão · x remove a credencial · a adiciona servidor · q fecha
local M = {}

local ns = vim.api.nvim_create_namespace("git_accounts")
local st = {}
local IDENTITY_DIR = vim.fn.expand("~/.config/git/neostorm-accounts")

local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "Contas do Git" }) end

local function sys(cmd, opts)
  opts = opts or {}
  opts.text = true
  opts.env = vim.tbl_extend("force", opts.env or {}, { GIT_TERMINAL_PROMPT = "0" })
  local ok, r = pcall(function() return vim.system(cmd, opts):wait(opts.timeout or 15000) end)
  return ok and r or { code = 1, stdout = "", stderr = tostring(r) }
end

-- servidor de uma URL de remoto: https://user@host/… · git@host:… · ssh://git@host/…
local function host_of(url)
  if not url or url == "" then return nil end
  local h = url:match("^https?://([^/]+)")
  if h then return (h:gsub("^.*@", ""):gsub(":%d+$", "")) end
  return url:match("^ssh://[^@/]*@?([^/:]+)") or url:match("^[%w._-]+@([^:]+):")
end
M.host_of = host_of

-- ---------------------------------------------------------------------------
-- Descoberta: servidores dos projetos (~/www e o projeto atual) e o que já está configurado
-- ---------------------------------------------------------------------------
local function scan_projects()
  local out = {}
  local function add(dir)
    local r = sys({ "git", "-C", dir, "remote", "get-url", "origin" }, { timeout = 3000 })
    local url = vim.trim(r.stdout or "")
    if r.code == 0 and url ~= "" then
      local host = host_of(url)
      if host then
        out[host] = out[host] or { repos = {} }
        table.insert(out[host].repos, { dir = dir, url = url, https = url:match("^https") ~= nil })
      end
    end
  end
  local seen = {}
  local cwd_root = vim.trim(sys({ "git", "rev-parse", "--show-toplevel" }, { cwd = vim.fn.getcwd() }).stdout or "")
  if cwd_root ~= "" then seen[cwd_root] = true; add(cwd_root) end
  for _, g in ipairs(vim.fn.globpath(vim.fn.expand("~/www"), "*/.git", false, true)) do
    local d = vim.fn.fnamemodify(g, ":h"); if not seen[d] then seen[d] = true; add(d) end
  end
  for _, g in ipairs(vim.fn.globpath(vim.fn.expand("~/www"), "*/*/.git", false, true)) do
    local d = vim.fn.fnamemodify(g, ":h"); if not seen[d] then seen[d] = true; add(d) end
  end
  for _, g in ipairs(vim.fn.globpath(vim.fn.expand("~/www"), "*/*/*/.git", false, true)) do
    local d = vim.fn.fnamemodify(g, ":h"); if not seen[d] then seen[d] = true; add(d) end
  end
  return out, cwd_root
end

local function config_get(key)
  local r = sys({ "git", "config", "--global", "--get", key })
  local v = vim.trim(r.stdout or "")
  return r.code == 0 and v ~= "" and v or nil
end

-- credencial no Chaves? (só verifica que existe; a senha nunca é lida)
local function keychain_account(host)
  local r = sys({ "security", "find-internet-password", "-s", host })
  if r.code ~= 0 then return nil end
  return (r.stdout or ""):match('"acct"<blob>="([^"]*)"') or ""
end

-- identidade de commit ligada a uma pasta (includeIf gitdir:… → arquivo deste host)
local function identity_for(host)
  local file = IDENTITY_DIR .. "/" .. host .. ".gitconfig"
  if not vim.uv.fs_stat(file) then return nil end
  local name, email
  for _, l in ipairs(vim.fn.readfile(file)) do
    name = name or l:match("^%s*name%s*=%s*(.-)%s*$")
    email = email or l:match("^%s*email%s*=%s*(.-)%s*$")
  end
  local r = sys({ "git", "config", "--global", "--get-regexp", "^includeif\\.gitdir:.*\\.path$" })
  local folder
  for line in (r.stdout or ""):gmatch("[^\n]+") do
    local f, p = line:match("^includeif%.gitdir:(.-)%.path%s+(.+)$")
    if p and vim.fn.expand(p) == file then folder = f end
  end
  return { name = name, email = email, folder = folder, file = file }
end

local function load()
  local projects, cwd_root = scan_projects()
  local hosts = {}
  for host in pairs(projects) do hosts[host] = true end
  -- servidores já configurados por aqui, mesmo sem projeto em ~/www
  for _, f in ipairs(vim.fn.globpath(IDENTITY_DIR, "*.gitconfig", false, true)) do hosts[vim.fn.fnamemodify(f, ":t:r")] = true end
  local r = sys({ "git", "config", "--global", "--get-regexp", "^credential\\.https://.*\\.username$" })
  for line in (r.stdout or ""):gmatch("[^\n]+") do
    local h = line:match("^credential%.https://([^%s]-)%.username")
    if h then hosts[h] = true end
  end
  for _, h in ipairs(st.extra or {}) do hosts[h] = true end
  local list = {}
  for host in pairs(hosts) do
    local p = projects[host] or { repos = {} }
    local https = 0
    for _, rp in ipairs(p.repos) do if rp.https then https = https + 1 end end
    table.insert(list, {
      host = host,
      repos = p.repos,
      https = https,
      user = config_get("credential.https://" .. host .. ".username"),
      keychain = keychain_account(host),
      identity = identity_for(host),
      current = cwd_root ~= "" and vim.iter(p.repos):any(function(rp) return rp.dir == cwd_root end),
    })
  end
  table.sort(list, function(a, b)
    if a.current ~= b.current then return a.current end
    return #a.repos > #b.repos or (#a.repos == #b.repos and a.host < b.host)
  end)
  return list
end

-- ---------------------------------------------------------------------------
-- Ações
-- ---------------------------------------------------------------------------
local function common_parent(repos)
  if #repos == 0 then return nil end
  local parts = vim.split(repos[1].dir, "/", { plain = true })
  for i = 2, #repos do
    local other = vim.split(repos[i].dir, "/", { plain = true })
    local n = 0
    for k = 1, math.min(#parts, #other) do if parts[k] == other[k] then n = k else break end end
    parts = vim.list_slice(parts, 1, n)
  end
  local dir = table.concat(parts, "/")
  if dir == "" or dir == vim.env.HOME or dir == vim.fn.expand("~/www") then return nil end
  return dir
end

--- Testa a conexão com um projeto deste servidor (sem pedir senha)
function M.test(acc, cb)
  local repo = acc.repos[1]
  if not repo then
    notify("Nenhum projeto de " .. acc.host .. " em ~/www para testar", vim.log.levels.WARN)
    return cb and cb(false)
  end
  notify("Testando " .. acc.host .. "…")
  vim.system({ "git", "-C", repo.dir, "ls-remote", "--heads", "origin" }, { text = true, env = { GIT_TERMINAL_PROMPT = "0" } }, function(r)
    vim.schedule(function()
      if r.code == 0 then
        notify("✓ " .. acc.host .. ": conexão ok (" .. vim.fn.fnamemodify(repo.dir, ":t") .. ")")
      else
        local err = vim.trim(r.stderr or ""):gsub("\n.*", "")
        notify("✗ " .. acc.host .. ": " .. err, vim.log.levels.ERROR)
      end
      if cb then cb(r.code == 0) end
    end)
  end)
end

local function save_identity(acc, name, email, folder)
  vim.fn.mkdir(IDENTITY_DIR, "p")
  local file = IDENTITY_DIR .. "/" .. acc.host .. ".gitconfig"
  vim.fn.writefile({
    "# Identidade de commit para os projetos de " .. acc.host .. " (Contas do Git, neostorm)",
    "[user]",
    "\tname = " .. name,
    "\temail = " .. email,
  }, file)
  folder = vim.fn.fnamemodify(vim.fn.expand(folder), ":p"):gsub("/?$", "/")
  -- tira um includeIf antigo deste arquivo (se a pasta mudou) e põe o novo
  if acc.identity and acc.identity.folder then
    sys({ "git", "config", "--global", "--unset-all", "includeIf.gitdir:" .. acc.identity.folder .. ".path" })
  end
  sys({ "git", "config", "--global", "includeIf.gitdir:" .. folder .. ".path", file })
  return folder
end

--- Configura usuário + token (Chaves) e, opcionalmente, a identidade de commit
function M.configure(acc, done)
  local function finish() if done then done() end end
  vim.ui.input({ prompt = "Usuário em " .. acc.host .. ": ", default = acc.user or acc.keychain or "" }, function(user)
    user = user and vim.trim(user) or ""
    if user == "" then return end
    vim.schedule(function()
      -- token oculto (não aparece na tela); vai direto para o git credential → Chaves do macOS
      local hint = acc.host:match("gitlab") and "token do GitLab (Preferences → Access Tokens, escopo write_repository)"
        or (acc.host == "github.com" and "token do GitHub (Settings → Developer settings → Tokens)" or "token ou senha")
      local ok, secret = pcall(vim.fn.inputsecret, "Cole o " .. hint .. " (Enter vazio mantém o atual): ")
      vim.cmd("redraw")
      if not ok then return end
      if secret and secret ~= "" then
        local r = vim.system({ "git", "credential", "approve" }, {
          text = true, stdin = "protocol=https\nhost=" .. acc.host .. "\nusername=" .. user .. "\npassword=" .. secret .. "\n\n",
        }):wait(10000)
        secret = nil
        if r.code ~= 0 then return notify("Não consegui salvar no Chaves: " .. (r.stderr or ""), vim.log.levels.ERROR) end
      end
      sys({ "git", "config", "--global", "credential.https://" .. acc.host .. ".username", user })

      -- identidade de commit para os projetos deste servidor
      local global = (config_get("user.name") or "?") .. " <" .. (config_get("user.email") or "?") .. ">"
      local KEEP, OTHER = "Usar a global: " .. global, "Outra só para " .. acc.host .. "…"
      local cur = acc.identity
      local options = { KEEP, OTHER }
      if cur then table.insert(options, 1, "Manter: " .. (cur.name or "?") .. " <" .. (cur.email or "?") .. "> em " .. (cur.folder or "?")) end
      vim.ui.select(options, { prompt = "Nome e e-mail dos commits em " .. acc.host }, function(choice)
        if not choice or choice:match("^Manter") then
          notify("Conta salva: " .. user .. " @ " .. acc.host)
          return M.test(acc, function() finish() end)
        end
        if choice == KEEP then
          if cur and cur.folder then sys({ "git", "config", "--global", "--unset-all", "includeIf.gitdir:" .. cur.folder .. ".path" }) end
          notify("Conta salva: " .. user .. " @ " .. acc.host .. " (identidade global)")
          return M.test(acc, function() finish() end)
        end
        vim.defer_fn(function()
          vim.ui.input({ prompt = "Nome nos commits: ", default = (cur and cur.name) or config_get("user.name") or "" }, function(name)
            if not name or vim.trim(name) == "" then return end
            vim.defer_fn(function()
              vim.ui.input({ prompt = "E-mail nos commits: ", default = (cur and cur.email) or "" }, function(email)
                if not email or vim.trim(email) == "" then return end
                vim.defer_fn(function()
                  local default_folder = (cur and cur.folder) or common_parent(acc.repos) or vim.fn.getcwd()
                  vim.ui.input({ prompt = "Vale para os projetos dentro de: ", default = vim.fn.fnamemodify(default_folder, ":~") }, function(folder)
                    if not folder or vim.trim(folder) == "" then return end
                    local f = save_identity(acc, vim.trim(name), vim.trim(email), vim.trim(folder))
                    notify("Conta salva: " .. user .. " @ " .. acc.host .. "\nCommits em " .. vim.fn.fnamemodify(f, ":~") .. " como " .. vim.trim(name) .. " <" .. vim.trim(email) .. ">")
                    M.test(acc, function() finish() end)
                  end)
                end, 50)
              end)
            end, 50)
          end)
        end, 50)
      end)
    end)
  end)
end

--- Remove a credencial deste servidor do Chaves (com confirmação)
function M.remove(acc, done)
  if not acc.keychain then return notify("Não há credencial de " .. acc.host .. " no Chaves") end
  if vim.fn.confirm("Remover a credencial de " .. acc.host .. " do Chaves do macOS?\nO próximo push/pull vai precisar dela de novo.", "&Remover\n&Cancelar", 2, "Question") ~= 1 then return end
  vim.system({ "git", "credential", "reject" }, {
    text = true, stdin = "protocol=https\nhost=" .. acc.host .. (acc.user and ("\nusername=" .. acc.user) or "") .. "\n\n",
  }):wait(10000)
  notify("Credencial de " .. acc.host .. " removida")
  if done then done() end
end

-- ---------------------------------------------------------------------------
-- Janela
-- ---------------------------------------------------------------------------
local function close()
  if st.win and vim.api.nvim_win_is_valid(st.win) then pcall(vim.api.nvim_win_close, st.win, true) end
  st.win = nil
end

local function render()
  if not (st.buf and vim.api.nvim_buf_is_valid(st.buf)) then return end
  local width = st.width
  local text, marks = {}, {}
  for i, acc in ipairs(st.list) do
    local user = acc.user or acc.keychain or "—"
    if user == "" then user = "—" end
    local cred = acc.keychain and "✓ no Chaves" or (acc.https > 0 and "✗ falta" or "SSH")
    local id = acc.identity and ((acc.identity.email or "?") .. " em " .. vim.fn.fnamemodify(acc.identity.folder or "?", ":~")) or "global"
    local count = #acc.repos == 1 and "1 projeto" or (#acc.repos .. " projetos")
    local host = (acc.current and "● " or "  ") .. acc.host
    -- (alinha pela largura na tela: ✓/✗/● ocupam mais bytes que colunas)
    local function pad(x, w) return x .. string.rep(" ", math.max(1, w - vim.fn.strdisplaywidth(x))) end
    local line = " " .. pad(host, 35) .. pad(user:sub(1, 16), 17) .. pad(cred, 13) .. id
    line = line .. string.rep(" ", math.max(2, width - vim.fn.strdisplaywidth(line) - #count - 1)) .. count
    table.insert(text, line)
    local r = i - 1
    table.insert(marks, { r, 0, 36, acc.current and "GitAccHostCur" or "GitAccHost" })
    local c0 = line:find(cred, 1, true)
    if c0 then table.insert(marks, { r, c0 - 1, c0 - 1 + #cred, acc.keychain and "GitAccOk" or (acc.https > 0 and "GitAccMissing" or "GitAccHint") }) end
    table.insert(marks, { r, #line - #count, #line, "GitAccHint" })
  end
  if #text == 0 then text = { "", "  Nenhum servidor encontrado. Aperte a para adicionar." } end
  vim.bo[st.buf].modifiable = true
  vim.api.nvim_buf_set_lines(st.buf, 0, -1, false, text)
  vim.bo[st.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(st.buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    local len = #text[m[1] + 1]
    local e = math.min(m[3], len)
    if m[2] < e then vim.api.nvim_buf_set_extmark(st.buf, ns, m[1], m[2], { end_col = e, hl_group = m[4] }) end
  end
end

local function current() return st.list and st.list[vim.api.nvim_win_get_cursor(st.win)[1]] end

local function reload_keep(host)
  st.list = load()
  if st.win and vim.api.nvim_win_is_valid(st.win) then
    render()
    for i, a in ipairs(st.list) do if a.host == host then pcall(vim.api.nvim_win_set_cursor, st.win, { i, 0 }) end end
  end
end

--- Abre a janela; opts.host já posiciona (ou adiciona) o servidor; opts.configure abre o fluxo direto
function M.open(opts)
  opts = opts or {}
  if opts.host then st.extra = vim.list_extend(st.extra or {}, { opts.host }) end
  st.list = load()
  close()
  st.width = math.min(120, vim.o.columns - 8)
  local height = math.max(4, math.min(#st.list, 14))
  st.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[st.buf].bufhidden = "wipe"
  st.win = vim.api.nvim_open_win(st.buf, true, {
    relative = "editor", row = math.floor((vim.o.lines - height) / 2) - 2, col = math.floor((vim.o.columns - st.width) / 2),
    width = st.width, height = height, style = "minimal", border = "rounded", zindex = 200,
    title = { { " Contas do Git ", "GitAccTitle" } }, title_pos = "left",
    footer = { { " Enter configura  t testa  x remove credencial  a adiciona servidor  q fecha ", "GitAccHint" } }, footer_pos = "right",
  })
  vim.wo[st.win].cursorline = true
  vim.wo[st.win].winhighlight = "Normal:GitAccNormal,FloatBorder:GitAccBorder,CursorLine:GitAccSel"
  render()
  local function map(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = st.buf, nowait = true }) end
  map("q", close)
  map("<Esc>", close)
  map("<CR>", function() local a = current(); if a then M.configure(a, function() reload_keep(a.host) end) end end)
  map("t", function() local a = current(); if a then M.test(a) end end)
  map("x", function() local a = current(); if a then M.remove(a, function() reload_keep(a.host) end) end end)
  map("a", function()
    vim.ui.input({ prompt = "Servidor (ex.: gitlab.empresa.com.br): " }, function(h)
      h = h and vim.trim(h):gsub("^https?://", ""):gsub("/.*$", "") or ""
      if h == "" then return end
      st.extra = vim.list_extend(st.extra or {}, { h })
      reload_keep(h)
    end)
  end)
  if opts.host then
    for i, a in ipairs(st.list) do
      if a.host == opts.host then
        vim.api.nvim_win_set_cursor(st.win, { i, 0 })
        if opts.configure then vim.schedule(function() M.configure(a, function() reload_keep(a.host) end) end) end
      end
    end
  end
end

--- Para push/pull/fetch: se falhou por falta de credencial, oferece configurar a conta
function M.handle_auth_error(stderr, repo_dir)
  stderr = stderr or ""
  local auth = stderr:match("could not read Username") or stderr:match("could not read Password")
    or stderr:match("terminal prompts disabled") or stderr:match("Authentication failed")
    or stderr:match("HTTP Basic: Access denied") or stderr:match("returned error: 40[13]")
  if not auth then return false end
  local url = vim.trim(sys({ "git", "-C", repo_dir or vim.fn.getcwd(), "remote", "get-url", "origin" }).stdout or "")
  local host = host_of(url) or stderr:match("https://([^/'\"]+)")
  vim.schedule(function()
    local ok = vim.fn.confirm("O git não tem credencial para " .. (host or "este servidor") .. ".\nConfigurar a conta agora?", "&Configurar\n&Agora não", 1, "Question")
    if ok == 1 then M.open({ host = host, configure = true }) end
  end)
  return true
end

local function colors()
  local ok, c = pcall(require, "config.palette")
  if not ok then return end
  local set = vim.api.nvim_set_hl
  set(0, "GitAccNormal", { fg = c.fg, bg = c.bg_float })
  set(0, "GitAccBorder", { fg = c.border, bg = c.bg_float })
  set(0, "GitAccTitle", { fg = c.fg, bg = c.bg_float, bold = true })
  set(0, "GitAccSel", { bg = require("config.palette").sel_row })
  set(0, "GitAccHint", { fg = c.fg_faint, bg = c.bg_float })
  set(0, "GitAccHost", { fg = c.fg })
  set(0, "GitAccHostCur", { fg = require("config.palette").bright, bold = true })
  set(0, "GitAccOk", { fg = c.hint })
  set(0, "GitAccMissing", { fg = c.error })
end
colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = colors })

return M
