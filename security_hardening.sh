#!/usr/bin/env bash
# Hardening: unattended-upgrades, SSH, Fail2Ban

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

info "Instalando unattended-upgrades…"
DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades >/dev/null
dpkg-reconfigure --priority=low unattended-upgrades

info "Endurecendo SSH…"
cp -a /etc/ssh/sshd_config{,.bak.$(date +%F)}
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
systemctl reload sshd

info "Instalando Fail2Ban…"
apt-get install -y fail2ban >/dev/null
cat >/etc/fail2ban/jail.local <<'EOF'
[sshd]
enabled = true
port    = 22
filter  = sshd
maxretry = 5

[nginx-http-auth]
enabled = true
port = http,https
EOF
systemctl enable --now fail2ban
fail2ban-client status sshd
info "Hardening concluído."
