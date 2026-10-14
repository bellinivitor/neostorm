#!/bin/sh
# Instala o neostorm: liga ~/.config/nvim e ~/.config/ghostty a esta pasta (links simbólicos).
# Se já existir uma config de verdade no lugar, ela é guardada como backup antes.
# Uso: ./install.sh
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
STAMP="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$CONFIG"

link() {
  name="$1"
  src="$DIR/$name"
  dst="$CONFIG/$name"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    echo "✓ $dst já aponta para o neostorm"
    return
  fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    mv "$dst" "$dst.backup-$STAMP"
    echo "• $dst existia: guardado em $dst.backup-$STAMP"
  fi
  ln -s "$src" "$dst"
  echo "✓ $dst → $src"
}

link nvim
link ghostty

# Ferramentas que a config usa
echo
missing=""
for tool in nvim git rg fd fzf tree-sitter node php composer; do
  command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
[ -d /Applications/Ghostty.app ] || missing="$missing ghostty"

if [ -n "$missing" ]; then
  echo "Faltam:$missing"
  echo "Com o Homebrew:"
  pkgs=""
  for t in $missing; do
    case "$t" in
      nvim) pkgs="$pkgs neovim" ;;
      rg) pkgs="$pkgs ripgrep" ;;
      tree-sitter) pkgs="$pkgs tree-sitter-cli" ;;
      ghostty) echo "  brew install --cask ghostty" ;;
      php|composer) ;; # vêm com o Herd (https://herd.laravel.com)
      *) pkgs="$pkgs $t" ;;
    esac
  done
  [ -n "$pkgs" ] && echo "  brew install$pkgs"
  case "$missing" in *php*|*composer*) echo "  PHP e Composer: instale o Laravel Herd (https://herd.laravel.com)" ;; esac
else
  echo "✓ Todas as ferramentas instaladas"
fi

echo
echo "Pronto. Abra o nvim: os plugins e os servidores de linguagem (Mason) instalam sozinhos na primeira vez."
echo "No Ghostty, recarregue a config com Cmd+Shift+,"
