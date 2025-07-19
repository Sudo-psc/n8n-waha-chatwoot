#!/usr/bin/env bash
set -Eeuo pipefail

# interface.sh - Interface de seleção de scripts

exibir_lista() {
  local scripts=("$@")
  local i=1
  for s in "${scripts[@]}"; do
    local desc
    desc=$(grep -m1 -E '^#' "$s" | sed 's/^#\s*//')
    printf '%3d) %s - %s\n' "$i" "$s" "$desc"
    i=$((i + 1))
  done
}

buscar_por_palavra() {
  local palavra="$1"; shift
  for s in "$@"; do
    if [[ "$s" == *"$palavra"* ]]; then
      echo "$s"
    fi
  done
}
