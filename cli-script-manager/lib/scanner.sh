#!/usr/bin/env bash
set -Eeuo pipefail

# scanner.sh - Descobre scripts shell no repositório

ler_scripts() {
  local base_dir="$1"
  find "$base_dir" -maxdepth 10 -type f \
    \( -name '*.sh' -o -name '*.bash' -o -name '*.zsh' \) \
    ! -path '*/docs/generated/*'
}

filtrar_shebang() {
  while read -r arquivo; do
    if head -n 1 "$arquivo" | grep -qE '^#!/.*(bash|sh|zsh)'; then
      echo "$arquivo"
    fi
  done
}
