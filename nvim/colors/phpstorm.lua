-- Tema "phpstorm": cores tiradas da tela do PhpStorm do Vitor (New UI, dark)
vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then vim.cmd("syntax reset") end
vim.o.background = "dark"
vim.g.colors_name = "phpstorm"

package.loaded["config.palette"] = nil
local c = require("config.palette")

local function hl(group, opts) vim.api.nvim_set_hl(0, group, opts) end
local function link(group, target) vim.api.nvim_set_hl(0, group, { link = target }) end

-- Editor
-- A cor padrão é o fundo escuro (canvas): o Neovide pinta margens e a sobra da borda
-- com ela. Cada janela recebe o tom de ilha via winhighlight (Island, em autocmds.lua)
hl("Normal", { fg = c.fg, bg = c.canvas })
hl("NormalNC", { fg = c.fg, bg = c.canvas })
hl("Island", { fg = c.fg, bg = c.bg })
hl("NormalFloat", { fg = c.fg, bg = c.bg_float })
hl("FloatBorder", { fg = c.border, bg = c.bg_float })
hl("FloatTitle", { fg = c.fg, bg = c.bg_float, bold = true })
hl("Cursor", { fg = c.bg, bg = c.fg })
hl("CursorLine", { bg = c.cursorline })
hl("CursorColumn", { bg = c.cursorline })
hl("ColorColumn", { bg = c.bg_alt })
hl("LineNr", { fg = c.linenr })
hl("LineNrAbove", { fg = c.linenr })
hl("LineNrBelow", { fg = c.linenr })
hl("CursorLineNr", { fg = c.linenr_cur })
hl("SignColumn", { bg = c.bg })
hl("FoldColumn", { fg = c.linenr, bg = c.bg })
-- Linha dobrada sem faixa de fundo; só o "..." ganha a caixinha (como no PhpStorm)
hl("Folded", { fg = c.fg_dim, bg = c.bg })
hl("FoldImports", { fg = c.fg_dim, bg = c.bg_hint })
-- vão entre as ilhas: o bloco parcial (fillchars em options.lua) tem a cor da ilha e o resto da célula mostra o fundo
hl("VertSplit", { fg = c.bg, bg = c.canvas })
hl("WinSeparator", { fg = c.bg, bg = c.canvas })
hl("MsgArea", { fg = c.fg, bg = c.canvas })
hl("EndOfBuffer", { fg = c.bg })
hl("NonText", { fg = c.indent })
hl("Whitespace", { fg = c.indent })
hl("SpecialKey", { fg = c.indent })
hl("Visual", { bg = c.selection })
hl("Search", { fg = c.fg, bg = "#2F5235" })
hl("CurSearch", { fg = "#FFFFFF", bg = "#3D6B44" })
hl("IncSearch", { link = "CurSearch" })
hl("Substitute", { link = "CurSearch" })
hl("MatchParen", { fg = "#FFEF28", bold = true })
hl("Pmenu", { fg = c.fg, bg = c.bg_float })
hl("PmenuSel", { fg = "#FFFFFF", bg = "#2E436E" })
hl("PmenuSbar", { bg = c.bg_float })
hl("PmenuThumb", { bg = c.border })
hl("PmenuKind", { fg = c.fg_dim, bg = c.bg_float })
hl("PmenuExtra", { fg = c.fg_dim, bg = c.bg_float })
hl("StatusLine", { fg = c.fg_dim, bg = c.canvas })
hl("StatusLineNC", { fg = c.fg_faint, bg = c.canvas })
hl("TabLine", { fg = c.fg_dim, bg = c.bg })
hl("TabLineFill", { bg = c.canvas })
hl("TabLineSel", { fg = c.fg, bg = c.bg })
hl("WinBar", { fg = c.fg_dim, bg = c.bg })
hl("WinBarNC", { fg = c.fg_faint, bg = c.bg })
hl("Title", { fg = c.fg, bold = true })
hl("Directory", { fg = c.fg })
hl("Question", { fg = c.hint })
hl("MoreMsg", { fg = c.hint })
hl("ModeMsg", { fg = c.fg })
hl("ErrorMsg", { fg = c.error })
hl("WarningMsg", { fg = c.warn })
hl("QuickFixLine", { bg = c.cursorline })
hl("Conceal", { fg = c.fg_dim })
hl("SpellBad", { undercurl = true, sp = c.error })
hl("SpellCap", { undercurl = true, sp = c.warn })

-- Sintaxe
hl("Comment", { fg = c.comment, italic = true })
hl("Constant", { fg = c.constant })
hl("String", { fg = c.string })
hl("Character", { fg = c.string })
hl("Number", { fg = c.number })
hl("Float", { fg = c.number })
hl("Boolean", { fg = c.keyword })
hl("Identifier", { fg = c.fg })
hl("Function", { fg = c.func_decl })
hl("Statement", { fg = c.keyword })
hl("Keyword", { fg = c.keyword })
hl("Conditional", { fg = c.keyword })
hl("Repeat", { fg = c.keyword })
hl("Exception", { fg = c.keyword })
hl("Operator", { fg = c.fg })
hl("PreProc", { fg = c.keyword })
hl("Include", { fg = c.keyword })
hl("Type", { fg = c.fg })
hl("StorageClass", { fg = c.keyword })
hl("Structure", { fg = c.keyword })
hl("Special", { fg = c.static })
hl("Delimiter", { fg = c.fg })
hl("Tag", { fg = c.tag })
hl("Todo", { fg = "#8BB33D", italic = true, bold = true })
hl("Underlined", { underline = true })
hl("Error", { fg = c.error })

-- Treesitter
local ts = {
  ["@keyword"] = { fg = c.keyword },
  ["@keyword.function"] = { fg = c.keyword },
  ["@keyword.return"] = { fg = c.keyword },
  ["@keyword.conditional"] = { fg = c.keyword },
  ["@keyword.repeat"] = { fg = c.keyword },
  ["@keyword.exception"] = { fg = c.keyword },
  ["@keyword.modifier"] = { fg = c.keyword },
  ["@keyword.operator"] = { fg = c.keyword },
  ["@keyword.import"] = { fg = c.keyword },
  ["@keyword.type"] = { fg = c.keyword },
  ["@type"] = { fg = c.fg },
  ["@type.builtin"] = { fg = c.keyword },
  ["@type.definition"] = { fg = c.fg },
  ["@constructor"] = { fg = c.fg },
  ["@module"] = { fg = c.fg },
  ["@function"] = { fg = c.func_decl },
  ["@function.method"] = { fg = c.func_decl },
  ["@function.call"] = { fg = c.method },
  ["@function.method.call"] = { fg = c.method },
  ["@function.builtin"] = { fg = c.static, italic = true },
  ["@variable"] = { fg = c.variable },
  ["@variable.builtin"] = { fg = c.this },
  ["@variable.parameter"] = { fg = c.variable },
  ["@variable.member"] = { fg = c.field },
  ["@property"] = { fg = c.field },
  ["@constant"] = { fg = c.constant },
  ["@constant.builtin"] = { fg = c.keyword },
  ["@string"] = { fg = c.string },
  ["@string.escape"] = { fg = c.keyword },
  ["@string.special"] = { fg = c.string },
  ["@number"] = { fg = c.number },
  ["@number.float"] = { fg = c.number },
  ["@boolean"] = { fg = c.keyword },
  ["@comment"] = { fg = c.comment, italic = true },
  ["@comment.documentation"] = { fg = c.comment, italic = true },
  ["@punctuation"] = { fg = c.fg },
  ["@punctuation.bracket"] = { fg = c.fg },
  ["@punctuation.delimiter"] = { fg = c.fg },
  ["@punctuation.special"] = { fg = c.keyword },
  ["@operator"] = { fg = c.fg },
  ["@attribute"] = { fg = c.tag },
  ["@tag"] = { fg = c.tag },
  ["@tag.builtin"] = { fg = c.tag },
  ["@tag.attribute"] = { fg = c.attr },
  ["@tag.delimiter"] = { fg = c.tag },
  ["@markup.heading"] = { fg = c.keyword, bold = true },
  ["@markup.link"] = { fg = c.method, underline = true },
  ["@markup.raw"] = { fg = c.string },
  ["@label"] = { fg = c.keyword },
}
for group, opts in pairs(ts) do hl(group, opts) end
-- PHPDoc (@param, @throws)
hl("@keyword.phpdoc", { fg = c.doc_tag, italic = true })
hl("@attribute.phpdoc", { fg = c.doc_tag, italic = true })
hl("@type.phpdoc", { fg = c.comment, italic = true, underline = false })
hl("@variable.phpdoc", { fg = c.comment, italic = true })
-- Blade e Vue
hl("@keyword.directive.blade", { fg = c.keyword })
hl("@tag.vue", { fg = c.tag })

-- LSP (tokens semânticos do Vue/TS)
link("@lsp.type.class", "@type")
link("@lsp.type.interface", "@type")
link("@lsp.type.enum", "@type")
link("@lsp.type.type", "@type")
link("@lsp.type.function", "@function")
link("@lsp.type.method", "@function.method.call")
link("@lsp.type.property", "@property")
link("@lsp.type.variable", "@variable")
link("@lsp.type.parameter", "@variable.parameter")
link("@lsp.type.namespace", "@module")
link("@lsp.typemod.function.declaration", "@function")
link("@lsp.typemod.method.declaration", "@function.method")
hl("LspInlayHint", { fg = c.fg_dim, bg = c.bg_hint })
hl("LspReferenceText", { bg = "#2D3036" })
hl("LspReferenceRead", { bg = "#2D3036" })
hl("LspReferenceWrite", { bg = "#3A2F3F" })
hl("LspSignatureActiveParameter", { fg = c.accent, bold = true })
hl("LspCodeLens", { fg = c.fg_faint })

-- Diagnósticos
hl("DiagnosticError", { fg = c.error })
hl("DiagnosticWarn", { fg = c.warn })
hl("DiagnosticInfo", { fg = c.info })
hl("DiagnosticHint", { fg = c.hint })
hl("DiagnosticOk", { fg = c.hint })
hl("DiagnosticUnderlineError", { undercurl = true, sp = c.error })
hl("DiagnosticUnderlineWarn", { undercurl = true, sp = c.warn })
hl("DiagnosticUnderlineInfo", { undercurl = true, sp = c.info })
hl("DiagnosticUnderlineHint", { undercurl = true, sp = c.hint })
hl("DiagnosticVirtualTextError", { fg = c.error, bg = "#2E2224" })
hl("DiagnosticVirtualTextWarn", { fg = c.warn, bg = "#2E2A22" })
hl("DiagnosticVirtualTextInfo", { fg = c.info, bg = "#222A36" })
hl("DiagnosticVirtualTextHint", { fg = c.hint, bg = "#232C25" })
hl("DiagnosticUnnecessary", { fg = c.fg_faint })
hl("DiagnosticDeprecated", { strikethrough = true })

-- Diff (Ver diff)
hl("DiffAdd", { bg = c.diff_add })
hl("DiffChange", { bg = "#25334A" })
hl("DiffText", { bg = "#33507A" })
hl("DiffDelete", { fg = c.diff_delete, bg = c.diff_delete })
hl("DiffNewOnly", { bg = "#2B4A32" })     -- linha nova (lado da sua versão)
hl("DiffOldOnly", { bg = "#4A2D30" })     -- linha apagada (lado do último commit)
hl("DiffFiller", { fg = "#3A3C41", bg = c.bg }) -- espaço onde não há linha (hachurado)
hl("DiffHeaderOld", { fg = "#FFFFFF", bg = "#4A3236", bold = true })
hl("DiffHeaderNew", { fg = "#FFFFFF", bg = "#2E4A36", bold = true })
hl("Added", { fg = c.add })
hl("Changed", { fg = c.change })
hl("Removed", { fg = c.delete })

-- Barra do git no lado do número
hl("GitSignsAdd", { fg = c.add })
hl("GitSignsChange", { fg = c.change })
hl("GitSignsChangedelete", { fg = c.change })
hl("GitSignsDelete", { fg = c.delete })
hl("GitSignsTopdelete", { fg = c.delete })
hl("GitSignsUntracked", { fg = c.add })
hl("GitSignsAddPreview", { bg = c.diff_add })
hl("GitSignsDeletePreview", { bg = c.diff_delete })

-- Painel do projeto (neo-tree)
-- a árvore do Projeto é uma ilha como o editor
hl("NeoTreeNormal", { fg = c.fg, bg = c.bg })
hl("NeoTreeNormalNC", { fg = c.fg, bg = c.bg })
hl("NeoTreeEndOfBuffer", { fg = c.bg, bg = c.bg })
hl("NeoTreeWinSeparator", { fg = c.bg, bg = c.canvas })
hl("NeoTreeCursorLine", { bg = "#2E436E" })
hl("NeoTreeDirectoryName", { fg = c.fg })
hl("NeoTreeDirectoryIcon", { fg = "#8A8F98" })
hl("NeoTreeFileName", { fg = c.fg })
hl("NeoTreeRootName", { fg = c.fg, bold = true })
hl("NeoTreeIndentMarker", { fg = c.indent_scope })
hl("NeoTreeGitModified", { fg = "#6CA2E8" })
hl("NeoTreeGitAdded", { fg = "#73BD79" })
hl("NeoTreeGitUntracked", { fg = "#D1675A" })
hl("NeoTreeGitDeleted", { fg = c.fg_faint })
hl("NeoTreeGitConflict", { fg = c.error })
hl("NeoTreeTabActive", { fg = c.fg, bg = c.bg_alt, bold = true })
hl("NeoTreeTabInactive", { fg = c.fg_faint, bg = c.bg_alt })
hl("NeoTreeTabSeparatorActive", { fg = c.bg_alt, bg = c.bg_alt })
hl("NeoTreeTabSeparatorInactive", { fg = c.bg_alt, bg = c.bg_alt })
hl("NeoTreeFloatBorder", { fg = c.border, bg = c.bg_float })

-- Guias de indentação e destaque de usos (snacks)
hl("SnacksIndent", { fg = c.indent })
hl("SnacksIndentScope", { fg = c.indent_scope })
hl("SnacksNotifierInfo", { fg = c.fg, bg = c.bg_float })
hl("SnacksNotifierBorderInfo", { fg = c.border, bg = c.bg_float })

-- Caixinhas de texto (vim.ui.input) iguais às listas de escolha
hl("SnacksInputNormal", { fg = c.fg, bg = c.bg_float })
hl("SnacksInputBorder", { fg = c.border, bg = c.bg_float })
hl("SnacksInputTitle", { fg = c.fg, bg = c.bg_float, bold = true })
hl("SnacksInputIcon", { fg = c.accent, bg = c.bg_float })
hl("SnacksPickerInputBorder", { fg = c.border, bg = c.bg_float })
hl("SnacksPickerBorder", { fg = c.border, bg = c.bg_float })
hl("SnacksPickerTitle", { fg = c.fg, bg = c.bg_float, bold = true })
hl("SnacksPickerPrompt", { fg = c.accent })

-- Tela inicial (dashboard)
hl("SnacksDashboardNormal", { fg = c.fg, bg = c.bg })
hl("SnacksDashboardHeader", { fg = "#FFFFFF", bold = true })
hl("SnacksDashboardDesc", { fg = c.fg })
hl("SnacksDashboardKey", { fg = c.accent, bold = true })
hl("SnacksDashboardIcon", { fg = c.fg_dim })
hl("SnacksDashboardTitle", { fg = c.fg, bold = true })
hl("SnacksDashboardFile", { fg = c.fg })
hl("SnacksDashboardDir", { fg = c.fg_faint })
hl("SnacksDashboardFooter", { fg = c.fg_faint })
hl("SnacksDashboardSpecial", { fg = c.fg_dim })

-- Busca (fzf-lua)
hl("FzfLuaNormal", { fg = c.fg, bg = c.bg_float })
hl("FzfLuaBorder", { fg = c.border, bg = c.bg_float })
hl("FzfLuaTitle", { fg = c.fg, bg = c.bg_float, bold = true })
hl("FzfLuaCursorLine", { bg = "#2E436E" })

-- Breadcrumbs (dropbar)
hl("DropBarMenuNormalFloat", { fg = c.fg, bg = c.bg_float })
hl("DropBarIconUISeparator", { fg = c.fg_faint })

-- Autocomplete (blink.cmp)
hl("BlinkCmpMenu", { fg = c.fg, bg = c.bg_float })
hl("BlinkCmpMenuBorder", { fg = c.border, bg = c.bg_float })
hl("BlinkCmpMenuSelection", { bg = "#2E436E" })
hl("BlinkCmpLabelMatch", { fg = c.accent, bold = true })
hl("BlinkCmpKind", { fg = c.fg_dim })
hl("BlinkCmpDoc", { fg = c.fg, bg = c.bg_float })
hl("BlinkCmpDocBorder", { fg = c.border, bg = c.bg_float })

-- Which-key
hl("WhichKeyNormal", { bg = c.bg_float })
hl("WhichKeyBorder", { fg = c.border, bg = c.bg_float })

-- Terminal com as mesmas cores
local term = { c.bg_float, c.error, c.string, c.warn, c.keyword, c.field, c.static, c.fg,
  c.fg_faint, "#FF7B86", "#7CC287", "#F2C26B", c.method, "#D88FCB", "#7DD8FA", "#DFE1E5" }
for i, color in ipairs(term) do vim.g["terminal_color_" .. (i - 1)] = color end

