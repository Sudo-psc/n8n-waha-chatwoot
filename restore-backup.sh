#!/usr/bin/env bash
# Restaura dados do Chatwoot, WAHA e n8n a partir do backup
set -Eeuo pipefail
trap 'echo "[ERRO] $BASH_COMMAND (linha $LINENO)"; exit 1' ERR

BACKUP_ROOT="/mnt/backup"
PG_COMPOSE="/opt/chatwoot/docker-compose.yml"

log(){ echo -e "\e[95m[REST]\e[0m $*"; }

[[ $EUID -eq 0 ]] || { echo "[ERRO] Rode como root"; exit 1; }

# localiza o dump mais recente se nenhuma data for passada
DATE=${1:-latest}
if [[ "$DATE" == "latest" ]]; then
  DUMP=$(ls -1t ${BACKUP_ROOT}/pg/chatwoot_*.dump | head -n1)
else
  DUMP="${BACKUP_ROOT}/pg/chatwoot_${DATE}.dump"
fi
[[ -f "$DUMP" ]] || { echo "[ERRO] Dump $DUMP não encontrado"; exit 1; }

# 1) Postgres -----------------------------------------------------------------
log "Restaurando banco Chatwoot de $DUMP..."
PG_ID=$(docker compose -f "$PG_COMPOSE" ps -q postgres)
docker cp "$DUMP" "$PG_ID:/tmp/restore.dump"
docker exec -e PGPASSWORD=chatwoot "$PG_ID" \
  pg_restore -U chatwoot -d chatwoot --clean --if-exists /tmp/restore.dump
docker exec "$PG_ID" rm /tmp/restore.dump

# 2) WAHA sessions ------------------------------------------------------------
log "Restaurando sessões WAHA..."
rsync -a --delete "${BACKUP_ROOT}/sessions/" /opt/waha/sessions/

# 3) Dados n8n ---------------------------------------------------------------
log "Restaurando dados n8n..."
rsync -a --delete "${BACKUP_ROOT}/n8n/" /opt/n8n/n8n_data/

# 4) Reinicia containers -----------------------------------------------------
log "Reiniciando serviços..."
docker compose -f /opt/chatwoot/docker-compose.yml up -d
docker compose -f /opt/waha/docker-compose.yml up -d
docker compose -f /opt/n8n/docker-compose.yml up -d

log "Restauração concluída."
