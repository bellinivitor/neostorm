# neostorm

Neovim que se comporta como o PhpStorm, feito para Laravel e Vue, rodando no [Ghostty](https://ghostty.org).
Atalhos de Mac (Cmd+…), painéis como os tool windows do PhpStorm e recursos que entendem Laravel.

## Instalar

```sh
git clone https://github.com/bellinivitor/neostorm.git ~/neostorm
cd ~/neostorm
./install.sh
```

O `install.sh` liga `~/.config/nvim` e `~/.config/ghostty` a esta pasta (se já houver uma config, guarda um backup)
e avisa o que falta instalar. Na primeira vez que o `nvim` abre, os plugins (lazy.nvim) e os servidores de
linguagem (Mason) são instalados sozinhos.

Precisa de: Neovim 0.12+, Ghostty, git, ripgrep, fd, fzf, tree-sitter CLI, Node e, para PHP,
o [Laravel Herd](https://herd.laravel.com) (PHP e Composer; o PHP de cada projeto vem do Herd).

## O que tem

**Editor**
- Abas em cards, barra de ferramentas à direita (Projeto, Commit, Structure, Problems, Run, Terminal, Claude, Git)
- Contagem de usos acima de classes e métodos (inclui as rotas que apontam para cada controller)
- Imports do PHP dobrados em `use ...` ao abrir o arquivo
- Rename de métodos e variáveis em todo o projeto (Phpactor) e Optimize Imports

**Laravel**
- **Endpoints**: todas as rotas numa lista com busca; Enter abre o controller no método
- No `routes/*.php`, o destino de cada rota no fim da linha e ícone clicável na margem
- Exemplo de requisição da rota: URL completa (APP_URL do `.env`) + payload montado das regras de validação
- `Cmd+clique` em `authorize('view', $model)` abre a Policy; em `route('nome')` abre o controller
- Tinker na seleção, com confirmação para código que altera dados
- Testes Pest com ▶ na margem, resultado ✓/✗ e mensagem de falha na linha
- Terminal, Run e Claude usam o PHP do projeto (o que o Herd usa para servir o site)

**Git**
- Popup de branches com submenu (checkout, merge, rebase, compare, push, rename, worktree…)
- Compare de branches e diff com os seus arquivos lado a lado
- Janela de Git com árvore de branches, log com grafo e arquivos de cada commit

**Run e Claude**
- Run Anything: scripts do `package.json`/`composer.json`, artisan, Makefile e recentes
- Painel Run com Rerun/Stop; caminho:linha de stack traces clicável
- Painel do Claude Code com o consumo (contexto, sessão, semana) no pé da coluna

## Atalhos principais

| Atalho | O quê |
|---|---|
| `Cmd+1` / `Cmd+0` / `Cmd+7` | Projeto / Commit / Structure |
| `Cmd+6` / `Cmd+9` | Problems / Git |
| `Cmd+Shift+X` | Run Anything |
| `Cmd+Option+R` | Endpoints (rotas) |
| `Cmd+Option+E` | Exemplo de requisição da rota |
| `Cmd+Option+T` | Tinker na seleção |
| `Cmd+Shift+E` | Recent Locations |
| `Cmd+B` / `Cmd+clique` | Ir para declaração (rotas, Policies, `route()` incluídos) |
| `Ctrl+T` | Rename |
| `Ctrl+Espaço` | Autocomplete (`Cmd+Espaço` também, se tirar o atalho do Spotlight) |
| `Option+F12` | Terminal |
| `Cmd+Esc` | Claude Code |
| `Espaço t n` / `t f` / `t l` | Teste sob o cursor / do arquivo / repetir |

## Observações

- `Cmd+Espaço` é do Spotlight no macOS; para usar no autocomplete, troque o atalho do Spotlight em
  Ajustes do Sistema → Teclado → Atalhos de Teclado → Spotlight.
- O painel do Claude usa uma status line própria (`nvim/claude-settings.json`) só para o Claude aberto pelo
  Neovim; a sua status line global do Claude Code não muda.
