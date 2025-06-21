#!/usr/bin/env bash
# Configura UFW: libera SSH (22), HTTP (80) e HTTPS (443),
# bloqueia acesso externo às portas 3000-3002 (usadas só pelo Nginx local)
set -euo pipefail

log(){ echo -e "\e[32m[UFW]\e[0m $*"; }

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
log "Status final:"
ufw status verbose
