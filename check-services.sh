#!/usr/bin/env bash
# Verifica portas abertas e testa URLs dos três serviços

# Structured logging ----------------------------------------------------------
SCRIPT_NAME=$(basename "$0" .sh)
LOG_FILE="/var/log/${SCRIPT_NAME}.log"
mkdir -p "$(dirname "$LOG_FILE")" && touch "$LOG_FILE"
log() { local level="$1"; shift; echo "$(date '+%F %T') [$level] $*" | tee -a "$LOG_FILE"; }
info() { log INFO "$@"; }
warn() { log WARN "$@"; }
error() { log ERROR "$@"; }

set -Eeuo pipefail
trap 'error "Linha $LINENO: comando \"$BASH_COMMAND\" falhou"' ERR

[[ $EUID -eq 0 ]] || { error "Rode como root"; exit 1; }

declare -A urls=(
  [Chatwoot]="https://chat.saraivavision.com.br"
  [WAHA]="https://waha.saraivavision.com.br"
  [n8n]="https://n8n.saraivavision.com.br"
)

info "Portas em escuta (22,80,443,3000-3002)"
ss -ltnp '( sport = :22 or sport = :80 or sport = :443 or sport = :3000 or sport = :3001 or sport = :3002 )' || true | tee -a "$LOG_FILE"


for name in "${!urls[@]}"; do
  url=${urls[$name]}
  code=$(curl -ks -o /dev/null -w '%{http_code}' "$url" || true)
  info "$(printf '%-8s => %-45s HTTP %s' "$name" "$url" "$code")"
done
