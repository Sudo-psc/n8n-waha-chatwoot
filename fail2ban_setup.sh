#!/usr/bin/env bash
# Instala e configura Fail2Ban para proteger SSH e Nginx

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

info "Instalando Fail2Ban…"
apt-get update -qq
apt-get install -y fail2ban >/dev/null

info "Configurando jail.local…"
cat >/etc/fail2ban/jail.local <<'JAIL'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port    = ssh
logpath = /var/log/auth.log

[nginx-http-auth]
enabled = true
port    = http,https
logpath = /var/log/nginx/*access.log

[nginx-botsearch]
enabled = true
port    = http,https
logpath = /var/log/nginx/*access.log
JAIL

info "Ativando e iniciando serviço…"
systemctl enable --now fail2ban

fail2ban-client status sshd || true
fail2ban-client status nginx-botsearch || true

info "Fail2Ban configurado."
