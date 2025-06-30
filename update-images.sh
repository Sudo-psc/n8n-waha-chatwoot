#!/usr/bin/env bash
# Atualiza imagens Docker das aplicações
# Uso: sudo ./update-images.sh [servico] [tag]
# Servicos: chatwoot | waha | n8n | all

set -Eeuo pipefail
log(){ echo -e "\e[33m[UPDATE]\e[0m $*"; }
[[ $EUID -eq 0 ]] || { echo "[ERRO] Rode como root"; exit 1; }

declare -A COMPOSE_PATHS=(
  [chatwoot]="/opt/chatwoot/docker-compose.yml"
  [waha]="/opt/waha/docker-compose.yml"
  [n8n]="/opt/n8n/docker-compose.yml"
)

declare -A IMAGES=(
  [chatwoot]="chatwoot/chatwoot"
  [waha]="devlikeapro/whatsapp-http-api"
  [n8n]="n8nio/n8n"
)

update_service(){
  local svc=$1 tag=${2:-latest}
  local compose=${COMPOSE_PATHS[$svc]}
  local image=${IMAGES[$svc]}

  [[ -f $compose ]] || { echo "[ERRO] Compose $compose não encontrado"; return 1; }
  log "Atualizando $svc para tag $tag..."
  sed -i -E "s|(${image}:).*|\1${tag}|" "$compose"
  docker compose -f "$compose" pull "$svc"
  docker compose -f "$compose" up -d "$svc"
}

main(){
  if [[ $# -eq 0 || $1 == all ]]; then
    for svc in "${!COMPOSE_PATHS[@]}"; do
      update_service "$svc" "${2:-latest}"
    done
  else
    update_service "$1" "${2:-latest}"
  fi
}

main "$@"
