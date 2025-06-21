#!/usr/bin/env bash
# Watchtower + limpeza semanal do Docker
set -euo pipefail
log(){ echo -e "\e[35m[MAINT]\e[0m $*"; }

log "Subindo Watchtower (auto-update dos containers)…"
docker run -d --name watchtower \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e WATCHTOWER_CLEANUP=true \
  -e WATCHTOWER_POLL_INTERVAL=86400 \
  --restart=always containrrr/watchtower

log "Criando cron semanal para docker system prune…"
echo "0 4 * * 0 root docker system prune -af --filter \"until=168h\"" \
  > /etc/cron.d/docker_prune
chmod 644 /etc/cron.d/docker_prune
log "Manutenção configurada."
