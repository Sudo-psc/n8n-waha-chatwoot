#!/usr/bin/env bash
# wnc-cli.sh - Gerencia stack Chatwoot + WAHA + n8n (v2.0)
set -Eeuo pipefail

# Cores para output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/wnc-cli.log"
CREDENTIALS_FILE="/root/.wnc-credentials"
mkdir -p "$(dirname "$LOG_FILE")" && touch "$LOG_FILE"

log() { 
    local level="$1"; shift
    echo "$(date '+%F %T') [$level] ${*:-}" | tee -a "$LOG_FILE"
}
info() { echo -e "${BLUE}[INFO]${NC} $1"; log INFO "$1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; log ERROR "$1"; exit 1; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; log SUCCESS "$1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; log WARN "$1"; }

usage() {
    cat <<USAGE
$(echo -e "${BLUE}WNC-CLI v2.0${NC} - Gerenciador da Stack Chatwoot + WAHA + n8n")

$(echo -e "${YELLOW}Uso:${NC}") $0 <comando> [argumentos]

$(echo -e "${YELLOW}Comandos Disponíveis:${NC}")
  install                 Instala Chatwoot, WAHA e n8n
  uninstall               Remove containers e arquivos
  update                  Atualiza containers e certificados
  backup [--now]          Executa backup imediato
  restore [DATA]          Restaura do backup (YYYY-MM-DD ou 'latest')
  logs <serviço>          Mostra logs do serviço (chatwoot|waha|n8n)
  status [serviço]        Mostra status dos containers
  restart <serviço>       Reinicia um serviço específico
  credentials [serviço]   Mostra credenciais salvas
  monitor                 Monitora recursos e status em tempo real
  exec <serviço> <cmd>    Executa comando em um container
  
$(echo -e "${YELLOW}Exemplos:${NC}")
  $0 status               # Status de todos os serviços
  $0 logs waha           # Logs do WAHA
  $0 credentials         # Todas as credenciais
  $0 restart chatwoot    # Reinicia Chatwoot
  $0 exec n8n bash       # Shell no container n8n
USAGE
}

require_root() { 
    [[ $EUID -eq 0 ]] || error "Execute como root (sudo)"
}

compose_file() {
    case "$1" in
        chatwoot) echo /opt/chatwoot/docker-compose.yml ;;
        waha) echo /opt/waha/docker-compose.yml ;;
        n8n) echo /opt/n8n/docker-compose.yml ;;
        *) return 1;;
    esac
}

service_exists() {
  local compose
  compose=$(compose_file "$1" 2>/dev/null) || return 1
  [[ -f "$compose" ]]
}

# Comandos principais
cmd_install() { 
    require_root
    info "Iniciando instalação..."
    "$SCRIPT_DIR/setup-wnc.sh" "$@"
}

cmd_uninstall() {
    require_root
    warn "Isso removerá completamente a stack WNC e todos os dados!"
    read -r -p "Tem certeza? Digite 'sim' para confirmar: " confirm
    
    [[ "$confirm" == "sim" ]] || { info "Cancelado."; return; }
    
    info "Removendo serviços..."
    for svc in chatwoot waha n8n; do
        compose=$(compose_file $svc) || continue
        if [[ -f "$compose" ]]; then
            info "Removendo $svc..."
            docker compose -f "$compose" down -v
            rm -rf "/opt/$svc"
        fi
    done
    
    # Remove configurações do Nginx
    for domain in chat.* waha.* n8n.*; do
        rm -f "/etc/nginx/sites-enabled/$domain"
        rm -f "/etc/nginx/sites-available/$domain"
    done
    systemctl reload nginx || true
    
    # Remove credenciais
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        warn "Removendo arquivo de credenciais..."
        rm -f "$CREDENTIALS_FILE"
    fi
    
    success "Stack WNC removida completamente."
}

cmd_update() { 
    require_root
    info "Atualizando serviços..."
    "$SCRIPT_DIR/manual_maintenance.sh"
}

cmd_backup() { 
    require_root
    local flag="${1:-}"
    if [[ "$flag" == "--now" ]] || [[ -z "$flag" ]]; then
        info "Executando backup..."
        "$SCRIPT_DIR/backup-setup.sh"
    else
        error "Argumento inválido. Use: $0 backup [--now]"
    fi
}

cmd_restore() { 
    require_root
    "$SCRIPT_DIR/restore-backup.sh" "$@"
}

cmd_logs() {
    [[ $# -eq 1 ]] || { usage; exit 1; }
    
    if ! service_exists "$1"; then
        error "Serviço '$1' não encontrado ou não instalado"
    fi
    
    compose=$(compose_file "$1")
    info "Mostrando logs de $1 (Ctrl+C para sair)..."
    docker compose -f "$compose" logs -f --tail=100
}

cmd_status() {
    echo -e "\n${BLUE}=== Status da Stack WNC ===${NC}\n"
    
    if [[ $# -eq 0 ]]; then
        # Status de todos os serviços
        for svc in chatwoot waha n8n; do
            if service_exists "$svc"; then
                compose=$(compose_file $svc)
                echo -e "${YELLOW}$svc:${NC}"
                docker compose -f "$compose" ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
                echo
            fi
        done
        
        # Status do Nginx
        echo -e "${YELLOW}Nginx:${NC}"
        systemctl is-active nginx >/dev/null && echo -e "  Status: ${GREEN}Ativo${NC}" || echo -e "  Status: ${RED}Inativo${NC}"
        echo
        
    else
        # Status de serviço específico
        if ! service_exists "$1"; then
            error "Serviço '$1' não encontrado"
        fi
        compose=$(compose_file "$1")
        docker compose -f "$compose" ps
    fi
}

cmd_restart() {
    [[ $# -eq 1 ]] || { usage; exit 1; }
    require_root
    
    if ! service_exists "$1"; then
        error "Serviço '$1' não encontrado"
    fi
    
    compose=$(compose_file "$1")
    info "Reiniciando $1..."
    docker compose -f "$compose" restart
    success "$1 reiniciado"
}

cmd_credentials() {
    require_root
    
    if [[ ! -f "$CREDENTIALS_FILE" ]]; then
        error "Arquivo de credenciais não encontrado. Execute a instalação primeiro."
    fi
    
    echo -e "\n${BLUE}=== Credenciais da Stack WNC ===${NC}\n"
    
    if [[ $# -eq 0 ]]; then
        # Mostra todas as credenciais formatadas
        for service in chatwoot waha n8n; do
            if grep -q "^${service}_" "$CREDENTIALS_FILE" 2>/dev/null; then
                echo -e "${YELLOW}${service^^}:${NC}"
                grep "^${service}_" "$CREDENTIALS_FILE" | while IFS='=' read -r key value; do
                    key_name=${key#"${service}"_}
                    # Oculta parcialmente valores sensíveis
                    if [[ "$key_name" =~ password|key|secret ]]; then
                        visible_chars=4
                        if [[ ${#value} -gt 8 ]]; then
                            masked_value="${value:0:$visible_chars}****${value: -$visible_chars}"
                        else
                            masked_value="****"
                        fi
                        echo "  $key_name: $masked_value"
                    else
                        echo "  $key_name: $value"
                    fi
                done
                echo
            fi
        done
        
        echo -e "${YELLOW}Dica:${NC} Para ver credenciais completas, use:"
        echo "  sudo cat $CREDENTIALS_FILE"
        echo
    else
        # Mostra credenciais de serviço específico
        service="$1"
        if ! grep -q "^${service}_" "$CREDENTIALS_FILE" 2>/dev/null; then
            error "Credenciais para '$service' não encontradas"
        fi
        
        echo -e "${YELLOW}${service^^}:${NC}"
        grep "^${service}_" "$CREDENTIALS_FILE" | while IFS='=' read -r key value; do
            key_name=${key#"${service}"_}
            echo "  $key_name: $value"
        done
        echo
    fi
}

cmd_monitor() {
    require_root
    
    if [[ -x /usr/local/bin/wnc-monitor ]]; then
        watch -n 2 -c /usr/local/bin/wnc-monitor
    else
        # Fallback se o script monitor não existir
        info "Monitorando serviços (Ctrl+C para sair)..."
        watch -n 2 -c "
            echo -e '${BLUE}=== Status da Stack WNC ===${NC}'
            echo
            for svc in chatwoot waha n8n; do
                if [[ -f /opt/\$svc/docker-compose.yml ]]; then
                    echo -n \"\$svc: \"
                    if docker compose -f /opt/\$svc/docker-compose.yml ps | grep -q 'Up'; then
                        echo -e '${GREEN}OK${NC}'
                    else
                        echo -e '${RED}DOWN${NC}'
                    fi
                fi
            done
            echo
            echo -e '${BLUE}=== Uso de Recursos ===${NC}'
            docker stats --no-stream --format 'table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}'
        "
    fi
}

cmd_exec() {
    [[ $# -ge 2 ]] || { usage; exit 1; }
    
    local service="$1"
    shift
    
    if ! service_exists "$service"; then
        error "Serviço '$service' não encontrado"
    fi
    
    compose=$(compose_file "$service")
    
    # Encontra o nome do container principal
    case "$service" in
        chatwoot) container="rails" ;;
        waha) container="waha" ;;
        n8n) container="n8n" ;;
    esac
    
    info "Executando comando no container $service/$container..."
    docker compose -f "$compose" exec "$container" "$@"
}

# Verifica se há atualizações disponíveis
check_updates() {
    if [[ -f "$SCRIPT_DIR/setup-wnc.sh" ]]; then
        local current_version
        current_version=$(grep "SCRIPT_VERSION=" "$SCRIPT_DIR/setup-wnc.sh" | cut -d'\"' -f2)
        if [[ "$current_version" != "2.0" ]]; then
            warn "Nova versão do instalador disponível! Execute: $0 update"
        fi
    fi
}

# Main
[[ $# -ge 1 ]] || { usage; exit 1; }

# Verifica atualizações em comandos não críticos
case "$1" in
    status|logs|credentials|monitor)
        check_updates
        ;;
esac

cmd="$1"; shift
case "$cmd" in
    install)      cmd_install "$@" ;;
    uninstall)    cmd_uninstall "$@" ;;
    update)       cmd_update "$@" ;;
    backup)       cmd_backup "$@" ;;
    restore)      cmd_restore "$@" ;;
    logs)         cmd_logs "$@" ;;
    status)       cmd_status "$@" ;;
    restart)      cmd_restart "$@" ;;
    credentials)  cmd_credentials "$@" ;;
    monitor)      cmd_monitor "$@" ;;
    exec)         cmd_exec "$@" ;;
    *)            usage; exit 1;;
esac

