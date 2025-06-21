#!/usr/bin/env bash
# Atualiza imagens Docker, renova certificados SSL e verifica dependências
set -euo pipefail
log(){ echo -e "\e[36m[MANUT]\e[0m $*"; }
[[ $EUID -eq 0 ]] || { echo "[ERRO] Rode como root"; exit 1; }

declare -a DEPS=(docker certbot)
log "Verificando dependências..."
for dep in "${DEPS[@]}"; do
  if ! command -v "$dep" &>/dev/null; then
    echo "[ERRO] Dependência '$dep' não encontrada" >&2
    exit 1
  fi
  "$dep" --version | head -n1
done

log "Atualizando containers Docker..."
for compose in /opt/chatwoot/docker-compose.yml \
               /opt/waha/docker-compose.yml \
               /opt/n8n/docker-compose.yml; do
  [[ -f "$compose" ]] || continue
  name=$(basename "$(dirname "$compose")")
  log "Atualizando $name..."
  docker compose -f "$compose" pull
  docker compose -f "$compose" up -d
done

log "Renovando certificados SSL..."
certbot renew --quiet
systemctl reload nginx

log "Manutenção concluída."
