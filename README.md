# neostorm

Neovim que se comporta como o PhpStorm, feito para Laravel e Vue, rodando no [Ghostty](https://ghostty.org).
Atalhos de Mac (Cmd+…), painéis como os tool windows do PhpStorm e recursos que entendem Laravel.

- [Instalar](#instalar)
- [Recursos](#recursos)
- [Atalhos](#atalhos)
- [Teclas dentro dos painéis](#teclas-dentro-dos-painéis)
- [Como funciona por baixo](#como-funciona-por-baixo)
- [Arquivos](#arquivos)
- [Observações](#observações)

## Instalar

```sh
git clone https://github.com/bellinivitor/neostorm.git ~/neostorm
cd ~/neostorm
./install.sh
```

O `install.sh` liga `~/.config/nvim` e `~/.config/ghostty` a esta pasta com links simbólicos (se já houver uma
config no lugar, guarda um backup `*.backup-<data>`) e avisa o que falta instalar, com o comando do Homebrew.
Na primeira vez que o `nvim` abre, os plugins (lazy.nvim), os parsers do treesitter e os servidores de
linguagem (Mason) são instalados sozinhos. Depois, no Ghostty, recarregue a config com `Cmd+Shift+,`.

**Requisitos:** macOS, Neovim 0.12+, Ghostty, git, ripgrep, fd, fzf, tree-sitter CLI e Node.
Para PHP: [Laravel Herd](https://herd.laravel.com) (PHP e Composer; o PHP de cada projeto vem do Herd).

**Salvar mudanças:** a config vive em `~/neostorm` (os caminhos em `~/.config` são links), então qualquer mudança
já está no repositório:

```sh
cd ~/neostorm && git add -A && git commit -m "descrição" && git push
```

## Recursos

### Interface
- **Abre no dashboard** (com a árvore do projeto): arquivos recentes do projeto e atalhos. **Restaurar sessão** (`v`)
  reabre os arquivos onde você parou (sessão por projeto e por branch). A sessão só é gravada quando o nvim abre sem
  arquivo (`nvim` na pasta do projeto); `nvim arquivo.php` não mexe nela.
- **Abas de arquivo em cards** arredondados; ● marca arquivo não salvo; o título "Projeto" fica alinhado à árvore.
- **Barra de ferramentas** na direita: Projeto, Commit, Structure em cima; Problems, Run, Terminal, Claude e Git embaixo.
  Projeto, Commit e Structure dividem o mesmo espaço (um de cada vez); Terminal, Run e Problems dividem o de baixo.
- **Breadcrumb clicável** no topo do editor (pasta › arquivo › classe › método).
- **Barra de status** como a do PhpStorm: modo, diagnósticos, encoding, posição e branch (clique abre as branches).
- Listas laterais não rolam além do último item.

### Editor
- **Contagem de usos** acima de classes e métodos (`3 usos`, `sem usos`); em controllers soma as **rotas** que
  apontam para cada classe/método (`7 rotas`).
- **Imports do PHP dobrados** em `use ...` ao abrir o arquivo (`zo` abre, `zc` fecha).
- **Rename** de métodos, variáveis, propriedades e classes em todo o projeto (Phpactor, só para isso;
  o resto vem do Intelephense).
- **Optimize Imports** (remove `use` sem uso e ordena), Reformat Code, ações de código (`Alt+Enter`).
- Autocomplete (blink.cmp), com sugestões de views, rotas, componentes e configs do Laravel (blade-nav).
- Barras do git na margem, clicáveis (ver diff / rollback da alteração).

### Laravel
- **PHP do projeto:** Terminal, Run, Claude, Run Anything e testes usam o PHP que o Herd usa para o site
  (`herd which-php`), e o Intelephense analisa com essa versão.
- **Endpoints** (`Cmd+Option+R`): todas as rotas numa lista com busca por URL, nome ou controller; Enter abre o
  controller no método (inclusive métodos herdados de traits/classe pai, também no `vendor`).
- **No `routes/*.php`:** o destino de cada rota no fim da linha (`→ AirlineController@store`,
  `→ AccountController  index, update`) e ícone clicável na margem; `Cmd+clique` no nome do controller abre o método.
- **Exemplo de requisição** (`Cmd+Option+E`): URL completa (APP_URL do `.env` ou o domínio da rota), método e
  payload montado das regras de validação (FormRequest, `$request->validate()` ou dos campos que o método lê).
  Funciona na linha da rota, dentro do método do controller e no popup de Endpoints (`Ctrl+E`).
- **Policies:** `Cmd+clique` em `authorize('view', $model)`, `->can(...)`, `Gate::authorize(...)` abre o método
  da Policy (pelo `$policies` do AuthServiceProvider ou pela convenção `App\Policies\XPolicy`).
- **`route('nome')`:** `Cmd+clique` abre o controller e a URL aparece no fim da linha.
- **Tinker na seleção** (`Cmd+Option+T`): roda o trecho (ou a linha) e mostra o resultado num popup; pede
  confirmação para código que altera dados (`save`, `update`, `delete`, `create`, `DB::statement`…).
- **Testes Pest:** ▶ na margem de cada `test()`/`it()` (e ⏵⏵ na 1ª linha para o arquivo); clique roda no painel Run;
  no fim mostra ✓/✗ e a mensagem de falha como erro na linha.

### Navegação
- **Search Everywhere**, Go to File, Go to Class/Symbol, Find in Files, arquivos recentes (fzf-lua).
- **Recent Locations** (`Cmd+Shift+E`): os últimos pontos do código por onde você passou, com o trecho de cada um.
- **Go to Declaration** (`Cmd+B` / `Cmd+clique`) entende rotas, Policies e `route()`, além do LSP.

### Git
- **Popup de branches** (clique na branch da barra de status): Recent/Local/Remote, busca, e submenu de cada
  branch: Checkout, New Branch, Checkout and Rebase, Compare, Show Diff with Working Tree, New Worktree, Rebase,
  Merge, Update, Push, Tracked Branch, Rename, Delete.
- **Compare de branches:** commits que uma tem e a outra não, nos dois sentidos, com detalhes e arquivos do commit.
- **Diff com os seus arquivos:** lista de arquivos alterados e diff lado a lado.
- **Janela de Git** (`Cmd+9`): árvore de branches, log com grafo colorido, arquivos e detalhes de cada commit.
- **Janela de Commit** (`Cmd+0`/`Cmd+K`): marcar arquivos, mensagem, Commit e Commit and Push.
- **Changelists** (como no PhpStorm): crie listas (`n` ou botão direito no cabeçalho), mova arquivos entre elas (`m`),
  renomeie, apague e escolha a **ativa** (recebe os arquivos alterados daqui para a frente). Rollback no cabeçalho
  desfaz todos os arquivos da lista, com uma confirmação só. Ficam em `.git/neostorm-changelists.json`.

### Run, Terminal e Claude
- **Run Anything** (`Cmd+Shift+X`): recentes, scripts do `package.json`/`composer.json`, artisan e Makefile;
  o texto digitado roda como comando de shell.
- **Painel Run:** uma aba por comando (▶ rodando, ✓ ok, ✗ falhou, ■ parado), botões Rerun e Stop.
- **Terminal** com abas (`Option+F12`), embaixo, à direita ou flutuante.
- **Stack trace clicável** no Run e no Terminal: `Cmd+clique`, `gf` ou Enter em `arquivo.php:120`,
  `#0 /…/x.php(74)`, `at tests/…:8`, `in /…/x.php on line 12`.
- **Problems** (`Cmd+6`): erros e avisos agrupados por arquivo; `a` analisa os arquivos alterados no git.
- **Claude Code** (`Cmd+Esc`) num painel próprio à direita, integrado ao editor (vê o arquivo e a seleção, diffs
  propostos abrem no Neovim), com o consumo no pé da coluna: contexto, limite de sessão e semanal.

## Atalhos

`<leader>` é o **Espaço**. Os atalhos com `Cmd` funcionam no Ghostty (ver [Como funciona](#como-funciona-por-baixo)).

### Edição
| Atalho | O quê |
|---|---|
| `Cmd+S` | Salvar (também salva sozinho ao trocar de arquivo/sair) |
| `Cmd+Z` / `Cmd+Shift+Z` | Desfazer / Refazer |
| `Cmd+C` / `Cmd+X` / `Cmd+V` | Copiar / Recortar (linha, se não houver seleção) / Colar |
| `Cmd+A` | Selecionar tudo |
| `Cmd+D` | Duplicar linha/seleção |
| `Cmd+Backspace` | Apagar linha |
| `Cmd+/` | Comentar linha/seleção |
| `Cmd+Shift+↑` / `↓` (ou `Option+Shift`) | Mover linha/seleção |
| `Option+Backspace` | Apagar palavra |
| `Cmd+F` / `Cmd+R` | Buscar / Substituir no arquivo |
| `Cmd+Shift+F` / `Cmd+Shift+R` | Buscar / Substituir no projeto |
| `Ctrl+Espaço` | Autocomplete, como no PhpStorm (de novo: mostra/esconde a documentação) |
| `Cmd+=` / `Cmd+-` / `Cmd+Option+0` | Fonte maior / menor / padrão (Neovide) |

### Navegação
| Atalho | O quê |
|---|---|
| `Espaço Espaço` | Search Everywhere |
| `Cmd+Shift+A` | Find Action (busca nos atalhos) |
| `Cmd+Shift+O` | Go to File |
| `Cmd+O` | Go to Class/Symbol |
| `Cmd+E` / `Cmd+Shift+E` | Arquivos recentes / Recent Locations |
| `Cmd+L` | Ir para a linha |
| `Cmd+[` / `Cmd+]` | Voltar / Avançar |
| `Cmd+Shift+[` / `Cmd+Shift+]` | Aba anterior / próxima (no terminal: aba do terminal) |
| `Cmd+W` | Fechar aba (no terminal: fecha a aba do terminal; nas telas de Git: fecha a tela) |
| `Cmd+F12` / `Cmd+7` | File Structure / painel Structure |
| `-` | Explorador da pasta atual (oil) |
| `Espaço f f` / `f g` / `f w` / `f b` / `f r` / `f p` | Arquivo / grep / grep da palavra / buffers / recentes / projetos |

### Código
| Atalho | O quê |
|---|---|
| `Cmd+B` / `Cmd+clique` | Go to Declaration or Usages (entende rotas, Policies e `route()`) |
| `Cmd+Option+B` / `gi` | Go to Implementation |
| `Option+F7` / `gr` | Find Usages / referências |
| `Ctrl+T` / `Shift+F6` / `Espaço r n` | Rename |
| `Alt+Enter` / `Espaço c a` | Ações de código |
| `F1` / `K` | Documentação |
| `Cmd+P` | Parameter Info |
| `F2` / `Shift+F2` | Próximo / anterior erro |
| `Cmd+Option+L` / `Espaço c f` | Reformat Code |
| `Ctrl+Option+O` / `Espaço c o` | Optimize Imports |
| `Espaço s s` / `s S` | Símbolos do arquivo / do projeto |
| `Espaço d` | Diagnóstico da linha |

### Laravel e testes
| Atalho | O quê |
|---|---|
| `Cmd+Option+R` / `Espaço l r` | Endpoints (rotas) |
| `Cmd+Option+E` / `Espaço l e` | Exemplo de requisição da rota |
| `Cmd+Option+T` / `Espaço l t` | Tinker na seleção (ou na linha) |
| `Cmd+N` / `Espaço l m` | Laravel make |
| `Espaço l a` / `l c` / `l o` / `l l` / `l p` | Artisan / commands / resources / picker geral / command center |
| `Espaço t n` / `t f` / `t s` / `t l` | Teste sob o cursor / do arquivo / suíte / repetir o último |

### Git
| Atalho | O quê |
|---|---|
| `Cmd+9` / `Espaço g g` | Janela de Git |
| `Cmd+0` / `Cmd+K` / `Espaço g s` | Janela de Commit |
| `Cmd+Shift+K` | Push |
| `Cmd+Option+N` | Nova branch |
| `Espaço g B` | Branches |
| `Espaço g b` | Blame na linha (liga/desliga) |
| `Espaço g h` / `g d` / `g r` | Alteração: menu / ver diff / rollback |
| `Cmd+Option+Z` | Rollback das linhas |
| `]h` / `[h` | Próxima / anterior alteração |

### Painéis, Run e Claude
| Atalho | O quê |
|---|---|
| `Cmd+1` / `Espaço e` | Projeto |
| `Cmd+6` / `Espaço x x` | Problems |
| `Cmd+Shift+X` / `Espaço R` | Run Anything |
| `Option+F12` / `Ctrl+/` / `Espaço t t` | Terminal |
| `Cmd+T` / `Espaço t N` | Nova aba de terminal |
| `Option+T` / `Espaço t m` | Terminal: mudar posição (embaixo → direita → flutuante) |
| `Espaço t b` / `t r` / `t g` | Terminal embaixo / à direita / flutuante |
| `Ctrl+K` (no terminal) | Voltar para o editor |
| `Esc Esc` (no terminal) | Modo normal (rolar e copiar a saída) |
| `Cmd+Esc` / `Espaço a c` / `a f` | Claude Code: abrir / focar |
| `Espaço a s` / `a b` | Claude: enviar seleção / adicionar arquivo |
| `Espaço a a` / `a d` | Claude: aceitar / recusar diff |
| `Espaço a r` / `a C` / `a m` | Claude: retomar / continuar / escolher modelo |

## Teclas dentro dos painéis

| Onde | Teclas |
|---|---|
| **Commit** | `Espaço`/`x` marca arquivo (no cabeçalho: a lista toda) · `Tab` abre/fecha grupo · `D` diff · `o`/`Cmd+↓` abre o arquivo · `n` nova changelist · `m` move para outra changelist · `Cmd+Option+Z` rollback (no cabeçalho: a lista toda) · botão direito: menu · `i` mensagem · `Cmd+Enter` commit · `r` atualiza · `q` fecha |
| **Popup de branches** | digite para buscar · `Enter`/clique abre o submenu da branch · no submenu `↑↓` e `Enter`, `Esc`/`←` volta |
| **Compare de branches** | `j`/`k` anda · `Enter` vai aos arquivos / abre o diff · `Tab` troca de painel · `q`/`Cmd+W` fecha |
| **Diff com seus arquivos** | `j`/`k` troca de arquivo · `]c`/`[c` próxima/anterior diferença · `o` abre o arquivo · `Tab` · `q` fecha |
| **Janela de Git** | `Enter` escolhe branch / abre pasta / abre diff · `/` busca · `Esc` limpa · `r` recarrega · `Tab` · `q` fecha |
| **Endpoints** | digite para buscar · `Enter` abre o controller · `Ctrl+E` exemplo de requisição · `Ctrl+R` recarrega |
| **Run Anything** | digite para buscar · `Enter` roda · `↑↓`/`Tab` navega · `Esc` fecha |
| **Run** | botões Rerun e Stop na barra · `×` fecha a aba |
| **Problems** | `Enter` vai ao problema / abre-fecha arquivo · `a` analisa os arquivos alterados · `q` fecha |
| **Exemplo de requisição** | `y` copia como curl · `Y` copia como HTTP · `q` fecha |
| **Tinker** | `y` copia o resultado · `q` fecha |

## Como funciona por baixo

- **Atalhos com Cmd:** o terminal não manda `Cmd+tecla` para o Neovim. O `ghostty/config` traduz cada um numa
  sequência (`csi:…`) que o Neovim recebe como `<D-tecla>`. Shift+F e Option+F chegam como F13 em diante
  (Shift+F6 = F18, Option+F7 = F55). Em outro terminal, use os atalhos com Espaço.
- **PHP do projeto:** `nvim/lua/config/project_php.lua` pergunta ao Herd (`herd which-php`) e põe um `php` com a
  versão do projeto na frente do PATH dos terminais do Neovim. Fora do Neovim nada muda.
- **Rotas:** vêm do `php artisan route:list --json` (com o PHP do projeto), lidas uma vez por sessão.
- **Rename:** o Phpactor roda só para isso (o rename do Intelephense é pago); sugestões, erros e definição seguem
  com o Intelephense. Se o projeto tiver `.phpactor.json`, a pergunta de confiança é respondida com "não carregar".
- **Consumo do Claude:** o Claude aberto pelo Neovim usa `nvim/claude-settings.json`, com uma status line
  (`nvim/scripts/claude-statusline.sh`) que grava o JSON de uso num arquivo que o painel lê. A status line global
  do Claude Code (`~/.claude/settings.json`) não muda. Sessão e semana aparecem depois da primeira resposta.

## Arquivos

```
ghostty/config                  aparência e atalhos com Cmd
nvim/init.lua                   ordem de carregamento
nvim/colors/phpstorm.lua        tema (cores do PhpStorm)
nvim/lua/plugins/               plugins (lazy.nvim): LSP, completion, treesitter, git, fzf, Laravel, Claude…
nvim/lua/config/
  phpstorm.lua                  atalhos no estilo PhpStorm
  tabs.lua                      abas em cards
  activity_bar.lua              barra de ferramentas da direita
  panels.lua                    painéis presos (arquivos não abrem dentro deles)
  term_panel.lua                painel de abas de terminal (base do Terminal, Run e Claude)
  terminal.lua / run_panel.lua / claude_panel.lua
  run_anything.lua              Run Anything
  commit.lua / branches.lua     janela de Commit e popup de branches
  git_compare.lua / git_log.lua Compare, diff com seus arquivos, janela de Git
  endpoints.lua                 Endpoints e rotas no routes/*.php
  route_example.lua             exemplo de requisição
  laravel_links.lua             Policies e route('nome')
  tinker.lua                    Tinker na seleção
  tests.lua                     testes Pest na margem
  stack_links.lua               caminho:linha clicável nos terminais
  problems.lua                  painel Problems
  usages.lua                    contagem de usos
  recent_locations.lua          Recent Locations
  imports.lua                   Optimize Imports e dobra dos imports
  project_php.lua               PHP do projeto (Herd)
  smart_click.lua / gitgutter.lua / git_rollback.lua / popup_menu.lua / dashboard.lua …
nvim/scripts/claude-statusline.sh
nvim/claude-settings.json
install.sh
```

## Observações

- **`Ctrl+Espaço`** (autocomplete) precisa estar livre no macOS: em Ajustes do Sistema → Teclado → Atalhos de
  Teclado → Fontes de Entrada, deixe desligado "Selecionar a fonte de entrada anterior".
- **Tinker** usa o banco do `.env` do projeto; código que parece alterar dados pede confirmação, mas confira antes.
- **Testes:** rodam a suíte de verdade do projeto (com o banco de teste configurado nele).
- **Problems** mostra o que os servidores de linguagem encontram, e eles só analisam arquivos abertos; use `a` para
  analisar os arquivos alterados no git.
