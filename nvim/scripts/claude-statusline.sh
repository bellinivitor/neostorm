#!/bin/sh
# Status line do Claude Code aberto pelo Neovim: só grava o JSON que o Claude manda
# (contexto e limites de uso) num arquivo que o painel do Claude lê e mostra.
# Não imprime nada: o resumo aparece na barra do painel, não dentro do Claude.
f="${NVIM_CLAUDE_STATUS:-$HOME/.cache/nvim/claude-status.json}"
mkdir -p "$(dirname "$f")"
cat > "$f.tmp" && mv "$f.tmp" "$f"
