#!/usr/bin/env bash
set -Eeuo pipefail

# main.sh - CLI Script Manager

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config/settings.conf
source "$ROOT_DIR/config/settings.conf"
# shellcheck source=./lib/scanner.sh
source "$ROOT_DIR/lib/scanner.sh"
# shellcheck source=./lib/interface.sh
source "$ROOT_DIR/lib/interface.sh"
# shellcheck source=./lib/executor.sh
source "$ROOT_DIR/lib/executor.sh"
# shellcheck source=./lib/documentation.sh
source "$ROOT_DIR/lib/documentation.sh"

mostrar_ajuda() {
  cat <<'HLP'
Uso: ./main.sh [opção]
  --list            Lista todos os scripts
  --interactive     Seleção interativa
  --update-docs     Atualiza documentação
HLP
}

listar_scripts() {
  ler_scripts "$ESCANEAR_DIRETORIO" | filtrar_shebang
}

case "${1:-}" in
  --list)
    listar_scripts
    ;;
  --update-docs)
    mapfile -t scripts < <(listar_scripts)
    criar_documentacao "$ROOT_DIR/docs/generated/SCRIPTS_INDEX.md" "${scripts[@]}"
    ;;
  --interactive)
    mapfile -t scripts < <(listar_scripts)
    exibir_lista "${scripts[@]}"
    ;;
  *)
    mostrar_ajuda
    exit 1
    ;;
esac
