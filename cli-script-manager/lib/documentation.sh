#!/usr/bin/env bash
set -Eeuo pipefail

# documentation.sh - Gera documentação automática dos scripts

criar_documentacao() {
  local arquivo_destino="$1"; shift
  local scripts=("$@")
  {
    echo "# Índice de Scripts"
    echo
    for s in "${scripts[@]}"; do
      local desc
      desc=$(grep -m1 -E '^#' "$s" | sed 's/^#\s*//')
      local mod
      mod=$(date -r "$s" '+%F %T')
      echo "- \`$s\` - $desc (modificado em $mod)"
    done
  } >"$arquivo_destino"
}
