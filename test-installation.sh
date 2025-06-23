#!/usr/bin/env bash
###############################################################################
# test-installation.sh - Testa e valida a instalação da stack WNC
# Autor: philipe_cruz@outlook.com
###############################################################################

# Cores para output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuração
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/wnc-test.log"
CREDENTIALS_FILE="/root/.wnc-credentials"
ERRORS=0
WARNINGS=0

# Logging
mkdir -p "$(dirname "$LOG_FILE")" && touch "$LOG_FILE"
log() { echo "$(date '+%F %T') [$1] $2" >> "$LOG_FILE"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; log INFO "$1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; log SUCCESS "$1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; log WARN "$1"; ((WARNINGS++)); }
error() { echo -e "${RED}[✗]${NC} $1"; log ERROR "$1"; ((ERRORS++)); }

# Banner
show_banner() {
    cat << 'BANNER'
    __        ___   _  ____    _____         _   
    \ \      / / \ | |/ ___|  |_   _|__  ___| |_ 
     \ \ /\ / /|  \| | |   _____| |/ _ \/ __| __|
      \ V  V / | |\  | |__|_____| |  __/\__ \ |_ 
       \_/\_/  |_| \_|\____|    |_|\___||___/\__|
    
    Validação da Instalação - v2.0
BANNER
    echo
}

# Verifica se é root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Este script deve ser executado como root (sudo)"
        exit 1
    fi
}

# Testa requisitos do sistema
test_system_requirements() {
    info "Testando requisitos do sistema..."
    
    # Sistema operacional
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "$ID" == "ubuntu" ]] || [[ "$ID" == "debian" ]]; then
            success "Sistema operacional: $PRETTY_NAME"
        else
            warn "Sistema não é Ubuntu/Debian: $PRETTY_NAME"
        fi
    else
        error "Não foi possível identificar o sistema operacional"
    fi
    
    # Memória RAM
    local total_mem=$(free -m | awk 'NR==2 {print $2}')
    if [[ $total_mem -ge 2048 ]]; then
        success "Memória RAM: ${total_mem}MB (OK)"
    else
        warn "Memória RAM: ${total_mem}MB (Recomendado: 2GB+)"
    fi
    
    # Espaço em disco
    local available_space=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $available_space -ge 10 ]]; then
        success "Espaço em disco: ${available_space}GB disponível (OK)"
    else
        error "Espaço em disco insuficiente: ${available_space}GB (Mínimo: 10GB)"
    fi
    
    # CPU
    local cpu_cores=$(nproc)
    if [[ $cpu_cores -ge 2 ]]; then
        success "CPU: $cpu_cores cores (OK)"
    else
        warn "CPU: $cpu_cores core (Recomendado: 2+)"
    fi
}

# Testa instalação do Docker
test_docker() {
    info "Testando Docker..."
    
    if command -v docker &>/dev/null; then
        local docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        success "Docker instalado: versão $docker_version"
        
        # Testa se Docker está rodando
        if systemctl is-active --quiet docker; then
            success "Docker está ativo"
        else
            error "Docker não está ativo"
        fi
        
        # Testa docker compose
        if docker compose version &>/dev/null; then
            local compose_version=$(docker compose version | awk '{print $4}')
            success "Docker Compose instalado: versão $compose_version"
        else
            error "Docker Compose não encontrado"
        fi
    else
        error "Docker não está instalado"
    fi
}

# Testa Nginx
test_nginx() {
    info "Testando Nginx..."
    
    if command -v nginx &>/dev/null; then
        local nginx_version=$(nginx -v 2>&1 | awk '{print $3}' | cut -d'/' -f2)
        success "Nginx instalado: versão $nginx_version"
        
        if systemctl is-active --quiet nginx; then
            success "Nginx está ativo"
            
            # Testa configuração
            if nginx -t &>/dev/null; then
                success "Configuração do Nginx válida"
            else
                error "Erro na configuração do Nginx"
            fi
        else
            error "Nginx não está ativo"
        fi
    else
        error "Nginx não está instalado"
    fi
}

# Testa rede Docker
test_docker_network() {
    info "Testando rede Docker..."
    
    if docker network inspect wcn_net &>/dev/null; then
        success "Rede wcn_net existe"
    else
        error "Rede wcn_net não encontrada"
    fi
}

# Testa serviço específico
test_service() {
    local service=$1
    local port=$2
    local health_endpoint=${3:-/health}
    
    info "Testando $service..."
    
    # Verifica se o diretório existe
    if [[ -d "/opt/$service" ]]; then
        success "Diretório /opt/$service existe"
    else
        error "Diretório /opt/$service não encontrado"
        return
    fi
    
    # Verifica docker-compose.yml
    if [[ -f "/opt/$service/docker-compose.yml" ]]; then
        success "docker-compose.yml encontrado"
    else
        error "docker-compose.yml não encontrado"
        return
    fi
    
    # Verifica se containers estão rodando
    local running_containers=$(docker compose -f /opt/$service/docker-compose.yml ps -q | wc -l)
    if [[ $running_containers -gt 0 ]]; then
        success "$running_containers container(s) rodando"
        
        # Mostra status dos containers
        docker compose -f /opt/$service/docker-compose.yml ps --format "table {{.Name}}\t{{.Status}}"
    else
        error "Nenhum container rodando para $service"
        return
    fi
    
    # Testa conectividade local
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port$health_endpoint" | grep -q "200\|401\|302"; then
        success "Serviço respondendo em localhost:$port"
    else
        warn "Serviço não respondendo corretamente em localhost:$port"
    fi
}

# Testa certificados SSL
test_ssl_certificates() {
    info "Testando certificados SSL..."
    
    # Busca domínios no arquivo de credenciais
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        local domains=()
        
        # Extrai URLs das credenciais
        while IFS='=' read -r key value; do
            if [[ "$key" =~ _url$ ]]; then
                domain=$(echo "$value" | sed 's|https://||' | sed 's|/.*||')
                domains+=("$domain")
            fi
        done < "$CREDENTIALS_FILE"
        
        # Testa cada domínio
        for domain in "${domains[@]}"; do
            if [[ -d "/etc/letsencrypt/live/$domain" ]]; then
                success "Certificado encontrado para $domain"
                
                # Verifica validade
                local cert_file="/etc/letsencrypt/live/$domain/fullchain.pem"
                if [[ -f "$cert_file" ]]; then
                    local expiry=$(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)
                    local expiry_epoch=$(date -d "$expiry" +%s)
                    local current_epoch=$(date +%s)
                    local days_left=$(( (expiry_epoch - current_epoch) / 86400 ))
                    
                    if [[ $days_left -gt 30 ]]; then
                        success "Certificado válido por mais $days_left dias"
                    elif [[ $days_left -gt 0 ]]; then
                        warn "Certificado expira em $days_left dias"
                    else
                        error "Certificado expirado!"
                    fi
                fi
            else
                warn "Certificado não encontrado para $domain"
            fi
        done
    else
        warn "Arquivo de credenciais não encontrado"
    fi
}

# Testa credenciais
test_credentials() {
    info "Testando arquivo de credenciais..."
    
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        success "Arquivo de credenciais existe"
        
        # Verifica permissões
        local perms=$(stat -c %a "$CREDENTIALS_FILE")
        if [[ "$perms" == "600" ]]; then
            success "Permissões corretas (600)"
        else
            error "Permissões incorretas: $perms (esperado: 600)"
        fi
        
        # Conta credenciais por serviço
        for service in chatwoot waha n8n; do
            local count=$(grep -c "^${service}_" "$CREDENTIALS_FILE" || true)
            if [[ $count -gt 0 ]]; then
                success "$count credencial(is) para $service"
            else
                warn "Nenhuma credencial encontrada para $service"
            fi
        done
    else
        error "Arquivo de credenciais não encontrado"
    fi
}

# Testa conectividade entre serviços
test_service_connectivity() {
    info "Testando conectividade entre serviços..."
    
    # Testa se containers podem se comunicar
    for service in chatwoot waha n8n; do
        if [[ -f "/opt/$service/docker-compose.yml" ]]; then
            # Pega o nome de um container do serviço
            local container=$(docker compose -f /opt/$service/docker-compose.yml ps -q | head -n1)
            if [[ -n "$container" ]]; then
                # Testa ping para outros serviços
                for target in chatwoot waha n8n; do
                    if [[ "$service" != "$target" ]] && [[ -f "/opt/$target/docker-compose.yml" ]]; then
                        if docker exec "$container" ping -c 1 -W 2 "$target" &>/dev/null; then
                            success "$service pode alcançar $target"
                        else
                            warn "$service não pode alcançar $target"
                        fi
                    fi
                done
            fi
        fi
    done
}

# Testa backups
test_backup_configuration() {
    info "Testando configuração de backup..."
    
    # Verifica script de backup
    if [[ -f "$SCRIPT_DIR/backup-setup.sh" ]]; then
        success "Script de backup encontrado"
    else
        error "Script de backup não encontrado"
    fi
    
    # Verifica diretório de backup
    if [[ -d "/mnt/backup" ]]; then
        success "Diretório de backup existe"
        
        # Verifica espaço disponível
        local backup_space=$(df -BG /mnt/backup | awk 'NR==2 {print $4}' | sed 's/G//')
        if [[ $backup_space -ge 5 ]]; then
            success "Espaço para backup: ${backup_space}GB disponível"
        else
            warn "Pouco espaço para backup: ${backup_space}GB"
        fi
    else
        warn "Diretório de backup não encontrado"
    fi
    
    # Verifica cron de backup
    if [[ -f "/etc/cron.d/chatwoot_backup" ]]; then
        success "Cron de backup configurado"
    else
        warn "Cron de backup não configurado"
    fi
}

# Testa performance básica
test_performance() {
    info "Testando performance básica..."
    
    # Load average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}')
    local load_1min=$(echo "$load_avg" | cut -d, -f1 | xargs)
    local cpu_cores=$(nproc)
    
    if (( $(echo "$load_1min < $cpu_cores" | bc -l) )); then
        success "Load average: $load_1min (OK)"
    else
        warn "Load average alto: $load_1min (CPU cores: $cpu_cores)"
    fi
    
    # Uso de memória
    local mem_used_percent=$(free | grep Mem | awk '{print ($3/$2) * 100.0}' | cut -d. -f1)
    if [[ $mem_used_percent -lt 80 ]]; then
        success "Uso de memória: ${mem_used_percent}% (OK)"
    else
        warn "Alto uso de memória: ${mem_used_percent}%"
    fi
    
    # Uso de disco
    local disk_used_percent=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $disk_used_percent -lt 80 ]]; then
        success "Uso de disco: ${disk_used_percent}% (OK)"
    else
        warn "Alto uso de disco: ${disk_used_percent}%"
    fi
}

# Gera relatório
generate_report() {
    echo
    echo -e "${BLUE}=== Relatório de Validação ===${NC}"
    echo
    
    local total_tests=$((ERRORS + WARNINGS + $(grep -c "SUCCESS" "$LOG_FILE")))
    local success_count=$(grep -c "SUCCESS" "$LOG_FILE")
    
    echo "Total de testes: $total_tests"
    echo -e "Sucessos: ${GREEN}$success_count${NC}"
    echo -e "Avisos: ${YELLOW}$WARNINGS${NC}"
    echo -e "Erros: ${RED}$ERRORS${NC}"
    echo
    
    if [[ $ERRORS -eq 0 ]]; then
        echo -e "${GREEN}✓ Instalação validada com sucesso!${NC}"
        
        if [[ $WARNINGS -gt 0 ]]; then
            echo -e "${YELLOW}  Alguns avisos foram encontrados. Verifique o log para detalhes.${NC}"
        fi
        
        echo
        echo "Próximos passos:"
        echo "1. Execute: ./wnc-cli.sh credentials"
        echo "2. Acesse os serviços e configure conforme necessário"
        echo "3. Configure backups regulares se ainda não estiverem ativos"
        
        return 0
    else
        echo -e "${RED}✗ Foram encontrados erros na validação!${NC}"
        echo
        echo "Ações recomendadas:"
        echo "1. Verifique o log completo em: $LOG_FILE"
        echo "2. Corrija os erros identificados"
        echo "3. Execute novamente este teste"
        
        return 1
    fi
}

# Main
main() {
    show_banner
    check_root
    
    echo "Iniciando validação da instalação..."
    echo "Log detalhado em: $LOG_FILE"
    echo
    
    # Executa todos os testes
    test_system_requirements
    echo
    
    test_docker
    echo
    
    test_nginx
    echo
    
    test_docker_network
    echo
    
    test_service "chatwoot" "3000"
    echo
    
    test_service "waha" "3001"
    echo
    
    test_service "n8n" "3002" "/"
    echo
    
    test_ssl_certificates
    echo
    
    test_credentials
    echo
    
    test_service_connectivity
    echo
    
    test_backup_configuration
    echo
    
    test_performance
    echo
    
    # Gera relatório final
    generate_report
}

# Executa
main "$@"