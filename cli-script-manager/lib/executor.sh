#!/usr/bin/env bash
set -Eeuo pipefail

# executor.sh - Executa scripts selecionados

verificar_execucao() {
  local arquivo="$1"
  if [[ ! -x "$arquivo" ]]; then
    echo "Script sem permissão de execução: $arquivo" >&2
    return 1
  fi
}

executar_script() {
  local arquivo="$1"; shift
  verificar_execucao "$arquivo"
  echo "Executando $arquivo em $(date '+%F %T')" >>"/tmp/script-manager.log"
  "$arquivo" "$@"
  echo "Saída: $?" >>"/tmp/script-manager.log"
}
