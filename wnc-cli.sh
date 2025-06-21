#!/usr/bin/env bash
# wnc-cli.sh - Gerencia stack Chatwoot + WAHA + n8n
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/wnc-cli.log"
mkdir -p "$(dirname "$LOG_FILE")" && touch "$LOG_FILE"

log(){ echo "$(date '+%F %T') [$1] ${2:-}" | tee -a "$LOG_FILE"; }
info(){ log INFO "$1"; }
error(){ log ERROR "$1"; exit 1; }

usage(){
  cat <<USAGE
Uso: $0 <comando> [args]
Comandos disponiveis:
  install                Instala Chatwoot, WAHA e n8n
  uninstall              Remove containers e arquivos
  update                 Atualiza containers e certificados
  backup                 Executa backup imediato
  restore [DATA]         Restaura do backup (YYYY-MM-DD ou 'latest')
  logs <servico>         Mostra logs do servico (chatwoot|waha|n8n)
  status [servico]       Mostra status dos containers
USAGE
}

require_root(){ [[ $EUID -eq 0 ]] || error "Execute como root"; }

compose_file(){
  case "$1" in
    chatwoot) echo /opt/chatwoot/docker-compose.yml ;;
    waha) echo /opt/waha/docker-compose.yml ;;
    n8n) echo /opt/n8n/docker-compose.yml ;;
    *) return 1;;
  esac
}

cmd_install(){ require_root; "$SCRIPT_DIR/setup-wnc.sh"; }

cmd_uninstall(){
  require_root
  for svc in chatwoot waha n8n; do
    compose=$(compose_file $svc) || continue
    if [[ -f "$compose" ]]; then
      docker compose -f "$compose" down -v
    fi
    rm -rf "/opt/$svc"
  done
  rm -f /etc/nginx/sites-enabled/{chat.saraivavision.com.br,waha.saraivavision.com.br,n8n.saraivavision.com.br}
  systemctl reload nginx || true
  info "Stack removida."
}

cmd_update(){ require_root; "$SCRIPT_DIR/manual_maintenance.sh"; }

cmd_backup(){ require_root; "$SCRIPT_DIR/backup-setup.sh"; }

cmd_restore(){ require_root; "$SCRIPT_DIR/restore-backup.sh" "$@"; }

cmd_logs(){
  [[ $# -eq 1 ]] || { usage; exit 1; }
  compose=$(compose_file "$1") || error "Servico invalido"
  docker compose -f "$compose" logs -f
}

cmd_status(){
  if [[ $# -eq 0 ]]; then
    for svc in chatwoot waha n8n; do
      compose=$(compose_file $svc) || continue
      [[ -f "$compose" ]] && docker compose -f "$compose" ps
    done
  else
    compose=$(compose_file "$1") || error "Servico invalido"
    docker compose -f "$compose" ps
  fi
}

[[ $# -ge 1 ]] || { usage; exit 1; }
cmd="$1"; shift
case "$cmd" in
  install)   cmd_install "$@" ;;
  uninstall) cmd_uninstall "$@" ;;
  update)    cmd_update "$@" ;;
  backup)    cmd_backup "$@" ;;
  restore)   cmd_restore "$@" ;;
  logs)      cmd_logs "$@" ;;
  status)    cmd_status "$@" ;;
  *)         usage; exit 1;;
esac

