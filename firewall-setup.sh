#!/usr/bin/env bash
# Configura UFW: libera SSH (22), HTTP (80) e HTTPS (443),
# bloqueia acesso externo às portas 3000-3002 (usadas só pelo Nginx local)

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

apt-get update -qq
apt-get install -y ufw >/dev/null

# política padrão
ufw default deny incoming
ufw default allow outgoing

# regras essenciais
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

# bloqueia acesso externo direto aos containers
for p in 3000 3001 3002; do
  ufw deny $p/tcp comment "Bloqueio porta interna $p"
done

# ativa
echo y | ufw enable
info "Status final:"
ufw status verbose
