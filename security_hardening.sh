#!/usr/bin/env bash
# Hardening: unattended-upgrades, SSH, Fail2Ban
set -Eeuo pipefail
trap 'echo "[ERRO] $BASH_COMMAND (linha $LINENO)"; exit 1' ERR

log(){ echo -e "\e[32m[SEC]\e[0m $*"; }
[[ $EUID -eq 0 ]] || { echo "[ERRO] Rode como root"; exit 1; }

log "Instalando unattended-upgrades…"
DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades >/dev/null
dpkg-reconfigure --priority=low unattended-upgrades

log "Endurecendo SSH…"
cp -a /etc/ssh/sshd_config{,.bak.$(date +%F)}
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
systemctl reload sshd

log "Instalando Fail2Ban…"
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
log "Hardening concluído."
