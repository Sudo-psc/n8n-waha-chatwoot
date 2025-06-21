#!/usr/bin/env bash
# Backup diário: Postgres (Chatwoot), Redis/WAHA, n8n

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

BACKUP_ROOT="/mnt/backup"
KEEP_DAYS=14
PG_COMPOSE="/opt/chatwoot/docker-compose.yml"
DATE=$(date +%F)
mkdir -p ${BACKUP_ROOT}/{pg,sessions,n8n}

log(){ echo -e "\e[94m[BACKUP]\e[0m $*"; }

# 1) Dump Postgres ----------------------------------------------------------------
info "Dumpando banco Chatwoot…"
PG_ID=$(docker compose -f $PG_COMPOSE ps -q postgres)
docker exec -e PGPASSWORD=chatwoot "$PG_ID" pg_dump -U chatwoot -Fc chatwoot \
  > "${BACKUP_ROOT}/pg/chatwoot_${DATE}.dump"

# 2) WAHA sessions (inclui QR, mensagens não lidas, etc.) -------------------------
info "Copiando sessões WAHA…"
rsync -a --delete /opt/waha/sessions/ "${BACKUP_ROOT}/sessions/"

# 3) Dados n8n (workflows, credenciais) -----------------------------------------
info "Copiando dados n8n…"
rsync -a --delete /opt/n8n/n8n_data/ "${BACKUP_ROOT}/n8n/"

# 4) Rotação simples -------------------------------------------------------------
find "${BACKUP_ROOT}" -type f -mtime +"$KEEP_DAYS" -delete
info "Backup concluído."

# 5) Agendar no cron -------------------------------------------------------------
CRON_JOB="/etc/cron.d/chatwoot_backup"
if [[ ! -f $CRON_JOB ]]; then
  echo "0 3 * * * root /usr/local/bin/backup_setup.sh" > $CRON_JOB
  chmod 644 $CRON_JOB
  info "Cron diário às 03:00 criado em $CRON_JOB"
fi
