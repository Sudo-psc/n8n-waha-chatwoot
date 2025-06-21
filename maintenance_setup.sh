#!/usr/bin/env bash
# Watchtower + limpeza semanal do Docker

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

info "Subindo Watchtower (auto-update dos containers)…"
docker run -d --name watchtower \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e WATCHTOWER_CLEANUP=true \
  -e WATCHTOWER_POLL_INTERVAL=86400 \
  --restart=always containrrr/watchtower

info "Criando cron semanal para docker system prune…"
echo "0 4 * * 0 root docker system prune -af --filter \"until=168h\"" \
  > /etc/cron.d/docker_prune
chmod 644 /etc/cron.d/docker_prune
info "Manutenção configurada."
