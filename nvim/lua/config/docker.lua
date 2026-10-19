-- Docker (Cmd+8, como o Services do PhpStorm): lista os containers e conecta num terminal.
--   Enter   abre um shell no container numa aba do painel Terminal (bash se tiver, senão sh);
--           container parado é iniciado antes
--   Ctrl+L  acompanha os logs (docker logs -f) numa aba
-- Os rodando aparecem primeiro; os parados ficam apagados.
local M = {}

M.icon = "\u{F0868}" -- 󰡨 (Material: docker)

local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "Docker" }) end

-- Containers de `docker ps -a`, rodando primeiro e depois pelo nome
local function containers()
  local r = vim.system({ "docker", "ps", "-a", "--format", "{{json .}}" }, { text = true }):wait(5000)
  if r.code ~= 0 then
    return nil, vim.trim(r.stderr or "") ~= "" and vim.trim(r.stderr) or "Não foi possível falar com o Docker. Ele está aberto?"
  end
  local list = {}
  for line in (r.stdout or ""):gmatch("[^\n]+") do
    local ok, c = pcall(vim.json.decode, line)
    if ok and c then
      c.running = c.State == "running"
      c.project = (c.Labels or ""):match("com%.docker%.compose%.project=([^,]+)")
      table.insert(list, c)
    end
  end
  table.sort(list, function(a, b)
    if a.running ~= b.running then return a.running end
    return a.Names < b.Names
  end)
  return list
end

local function tab(name, cmd)
  require("config.terminal").new({ name = name, cmd = cmd, docker = true })
end

--- Shell no container (inicia antes se estiver parado)
function M.connect(c)
  local shell = { "docker", "exec", "-it", c.Names, "sh", "-c", "command -v bash >/dev/null && exec bash || exec sh" }
  if c.running then return tab(c.Names, shell) end
  notify("Iniciando " .. c.Names .. "…")
  vim.system({ "docker", "start", c.Names }, { text = true }, function(r)
    vim.schedule(function()
      if r.code ~= 0 then return notify("Não foi possível iniciar " .. c.Names .. ":\n" .. vim.trim(r.stderr or ""), vim.log.levels.ERROR) end
      tab(c.Names, shell)
    end)
  end)
end

function M.logs(c)
  tab(c.Names .. " (logs)", { "docker", "logs", "-f", "--tail", "300", c.Names })
end

-- "Up 3 days" / "Exited (0) 2 weeks ago" → "há 3 dias"
local UNITS = {
  second = { "segundo", "segundos" }, minute = { "minuto", "minutos" }, hour = { "hora", "horas" },
  day = { "dia", "dias" }, week = { "semana", "semanas" }, month = { "mês", "meses" }, year = { "ano", "anos" },
}
local function since(status)
  local s = status:gsub("%s*%(.-%)", ""):gsub("^Up%s+", ""):gsub("^Exited%s+", ""):gsub("%s+ago$", "")
  if s:match("^Less than a second") then return "agora" end
  local n, unit = s:match("^(%d+)%s+(%a-)s?$")
  if not n then
    unit = s:match("^About an? (%a+)$") or s:match("^an? (%a+)$")
    n = unit and "1"
  end
  local u = unit and UNITS[unit]
  if not u then return s end
  return "há " .. n .. " " .. (n == "1" and u[1] or u[2])
end

-- "0.0.0.0:97->80/tcp, [::]:97->80/tcp, 9000/tcp" → { "localhost:97 → 80", "9000 (só na rede do Docker)" }
local function ports(str)
  local out, seen = {}, {}
  for p in (str or ""):gmatch("[^,]+") do
    p = vim.trim(p)
    local host, inner = p:match(":(%d+)%->(%d+)")
    local line = host and ("localhost:" .. host .. " → " .. inner)
      or (p:match("^(%d+)") and p:match("^(%d+)") .. " (só na rede do Docker)")
    if line and not seen[line] then seen[line] = true; table.insert(out, line) end
  end
  -- as publicadas (localhost) primeiro: são as que se acessam do Mac
  table.sort(out, function(a, b)
    local la, lb = a:match("^localhost") ~= nil, b:match("^localhost") ~= nil
    if la ~= lb then return la end
    return a < b
  end)
  return out
end

-- "registry.x/arquitetura/php-oci-nginx:1.4" → "php-oci-nginx:1.4", "registry.x/arquitetura"
local function image_parts(image)
  local short = image:match("[^/]+$") or image
  local origin = image:sub(1, #image - #short - 1)
  return short, origin ~= "" and origin or nil
end

local ns = vim.api.nvim_create_namespace("docker_preview")

-- Ficha do container no painel da direita
local function preview(ctx)
  local c = ctx.item.container
  ctx.preview:reset()
  ctx.preview:minimal()
  local lines, marks = {}, {}
  local function add(text, hl, col) table.insert(lines, text); if hl then table.insert(marks, { #lines - 1, col or 0, hl }) end end
  local function field(label, value, hl)
    add("  " .. label .. string.rep(" ", 10 - vim.fn.strdisplaywidth(label)) .. value, "DockerLabel")
    table.insert(marks, { #lines - 1, 12, hl or "DockerValue" })
  end
  local short, origin = image_parts(c.Image)
  add("")
  add("  " .. c.Names, "DockerName")
  add("  " .. (c.running and "\u{25CF} Rodando " or "\u{25CB} Parado ") .. since(c.Status), c.running and "DockerUp" or "DockerDown")
  add("")
  field("Imagem", short)
  if origin then field("", origin, "DockerDim") end
  if c.project then field("Projeto", c.project) end
  local p = ports(c.Ports)
  for i, line in ipairs(p) do field(i == 1 and "Portas" or "", line) end
  add("")
  add("")
  local enter = "Enter  " .. (c.running and "abrir um terminal" or "iniciar e abrir um terminal")
  add("  " .. enter .. "    Ctrl+L  ver os logs", "DockerKeys")
  -- as teclas um tom acima da descrição
  table.insert(marks, { #lines - 1, 2, "DockerLabel", 2 + #"Enter" })
  table.insert(marks, { #lines - 1, 2 + #enter + 4, "DockerLabel", 2 + #enter + 4 + #"Ctrl+L" })
  ctx.preview:set_lines(lines)
  local buf = ctx.preview.win.buf
  for _, m in ipairs(marks) do
    local text = lines[m[1] + 1]
    if m[2] < #text then
      local end_col = m[4] or (m[3] == "DockerLabel" and math.min(12, #text) or #text)
      vim.api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = end_col, hl_group = m[3], priority = m[4] and 200 or nil })
    end
  end
end

function M.open()
  local list, err = containers()
  if not list then return notify(err, vim.log.levels.ERROR) end
  if #list == 0 then return notify("Nenhum container. Suba um com docker compose up.") end
  local name_w, image_w = 0, 0
  for _, c in ipairs(list) do
    name_w = math.max(name_w, vim.fn.strdisplaywidth(c.Names))
    image_w = math.max(image_w, vim.fn.strdisplaywidth((image_parts(c.Image))))
  end
  local items = {}
  for _, c in ipairs(list) do
    table.insert(items, { text = c.Names .. " " .. c.Image .. " " .. (c.project or ""), container = c })
  end
  Snacks.picker.pick({
    title = "Containers",
    items = items,
    preview = preview,
    layout = {
      layout = {
        box = "horizontal", width = 0.72, min_width = 110, height = 0.55, min_height = 16,
        {
          box = "vertical", border = "rounded", title = "{title}", title_pos = "center",
          { win = "input", height = 1, border = "bottom" },
          { win = "list", border = "none" },
        },
        { win = "preview", border = "rounded", width = 0.45 },
      },
    },
    format = function(item)
      local c = item.container
      local short = image_parts(c.Image)
      return {
        { c.running and " \u{25CF} " or " \u{25CB} ", c.running and "DockerUp" or "DockerDown" },
        { c.Names .. string.rep(" ", name_w - vim.fn.strdisplaywidth(c.Names) + 3), c.running and "DockerValue" or "DockerDim" },
        { short .. string.rep(" ", image_w - vim.fn.strdisplaywidth(short) + 3), "DockerDim" },
        { c.running and since(c.Status) or "parado", c.running and "DockerLabel" or "DockerDim" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then M.connect(item.container) end
    end,
    actions = {
      docker_logs = function(picker, item)
        picker:close()
        if item then M.logs(item.container) end
      end,
    },
    win = {
      input = { keys = { ["<c-l>"] = { "docker_logs", mode = { "n", "i" }, desc = "Logs" } } },
      list = { keys = { ["<c-l>"] = { "docker_logs", desc = "Logs" } } },
    },
  })
end

-- Cores (seguem o tema)
local function colors()
  local ok, c = pcall(require, "config.palette")
  if not ok then return end
  local set = vim.api.nvim_set_hl
  set(0, "DockerName", { fg = c.bright, bold = true })
  set(0, "DockerUp", { fg = c.git_added })
  set(0, "DockerDown", { fg = c.fg_faint })
  set(0, "DockerLabel", { fg = c.fg_dim })
  set(0, "DockerValue", { fg = c.fg })
  set(0, "DockerDim", { fg = c.fg_faint })
  set(0, "DockerKeys", { fg = c.fg_faint })
end
colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = colors })

return M
