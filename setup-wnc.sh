#!/usr/bin/env bash
###############################################################################
#  Auto-installer: Chatwoot + WAHA + n8n (Docker) com Nginx e HTTPS
#  Versão: 2.0.0
#  Autor: philipe_cruz@outlook.com
#  
#  Melhorias:
#  - Configuração via variáveis de ambiente ou prompt interativo
#  - Validações de sistema e pré-requisitos
#  - Sistema de rollback em caso de falha
#  - Armazenamento seguro de credenciais
#  - Verificação de saúde dos serviços
#  - Suporte a instalação parcial
###############################################################################

# Configuração de cores para output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Structured logging ----------------------------------------------------------
SCRIPT_NAME=$(basename "$0" .sh)
LOG_FILE="/var/log/${SCRIPT_NAME}.log"
CREDENTIALS_FILE="/root/.wnc_credentials"
BACKUP_DIR="/var/backups/wnc-setup"

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$CREDENTIALS_FILE")" "$BACKUP_DIR"
touch "$LOG_FILE"

log() { 
    local level="$1"
    shift
    echo "$(date '+%F %T') [$level] $*" | tee -a "$LOG_FILE"
}

info() { echo -e "${GREEN}[INFO]${NC} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; }
debug() { [[ "${DEBUG:-0}" == "1" ]] && echo -e "${BLUE}[DEBUG]${NC} $*" | tee -a "$LOG_FILE"; }

# Configuração de tratamento de erros
set -Eeuo pipefail
trap 'handle_error $? $LINENO "$BASH_COMMAND"' ERR

# Lista de recursos criados para rollback
declare -a CREATED_RESOURCES=()

handle_error() {
    local exit_code=$1
    local line_number=$2
    local command=$3
    
    error "Erro na linha $line_number: comando '$command' falhou com código $exit_code"
    
    if [[ "${AUTO_ROLLBACK:-1}" == "1" ]]; then
        warn "Iniciando rollback automático..."
        rollback
    fi
    
    exit $exit_code
}

# Função de rollback
rollback() {
    info "Executando rollback dos recursos criados..."
    
    for resource in "${CREATED_RESOURCES[@]}"; do
        case "$resource" in
            "docker:*")
                local container="${resource#docker:}"
                info "Removendo container Docker: $container"
                docker compose -f "$container" down -v 2>/dev/null || true
                ;;
            "nginx:*")
                local site="${resource#nginx:}"
                info "Removendo configuração Nginx: $site"
                rm -f "/etc/nginx/sites-enabled/$site" "/etc/nginx/sites-available/$site"
                ;;
            "dir:*")
                local dir="${resource#dir:}"
                info "Removendo diretório: $dir"
                rm -rf "$dir"
                ;;
        esac
    done
    
    systemctl reload nginx 2>/dev/null || true
    info "Rollback concluído"
}

# Configurações padrão (podem ser sobrescritas por variáveis de ambiente)
: "${CHAT_DOMAIN:=}"
: "${WAHA_DOMAIN:=}"
: "${N8N_DOMAIN:=}"
: "${EMAIL_SSL:=}"
: "${STACK_NET:=wcn_net}"
: "${INTERACTIVE:=1}"
: "${INSTALL_CHATWOOT:=1}"
: "${INSTALL_WAHA:=1}"
: "${INSTALL_N8N:=1}"
: "${MIN_MEMORY_GB:=4}"
: "${MIN_DISK_GB:=20}"

# Portas configuráveis
: "${CHATWOOT_PORT:=3000}"
: "${WAHA_PORT:=3001}"
: "${N8N_PORT:=3002}"

#-----------------------------------------------------------------------------
# Funções utilitárias
#-----------------------------------------------------------------------------
apt_install() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" >/dev/null 2>&1
}

cmd_exists() { 
    command -v "$1" &>/dev/null 
}

ensure_dir() {
    if [[ ! -d "$1" ]]; then
        mkdir -p "$1"
        chmod 755 "$1"
        CREATED_RESOURCES+=("dir:$1")
        debug "Diretório criado: $1"
    fi
}

write_config() {
    local file=$1
    shift
    
    # Backup se arquivo existir
    if [[ -f "$file" ]]; then
        local backup="${BACKUP_DIR}/$(basename "$file").$(date +%s)"
        cp "$file" "$backup"
        debug "Backup criado: $backup"
    fi
    
    cat > "$file" "$@"
}

save_credential() {
    local service=$1
    local key=$2
    local value=$3
    
    echo "${service}_${key}=${value}" >> "$CREDENTIALS_FILE"
    chmod 600 "$CREDENTIALS_FILE"
}

check_port() {
    local port=$1
    if ss -tlnp | grep -q ":${port}"; then
        error "Porta $port já está em uso"
        return 1
    fi
    return 0
}

check_domain_dns() {
    local domain=$1
    local server_ip=$(curl -s https://api.ipify.org 2>/dev/null || echo "unknown")
    
    info "Verificando DNS para $domain..."
    
    local dns_ip=$(dig +short "$domain" @8.8.8.8 2>/dev/null | tail -1)
    
    if [[ -z "$dns_ip" ]]; then
        warn "DNS não configurado para $domain"
        warn "Configure o DNS apontando para: $server_ip"
        return 1
    elif [[ "$dns_ip" != "$server_ip" ]]; then
        warn "DNS de $domain aponta para $dns_ip, mas servidor está em $server_ip"
        return 1
    fi
    
    info "DNS OK: $domain → $dns_ip"
    return 0
}

wait_for_service() {
    local service=$1
    local url=$2
    local max_attempts=30
    local attempt=1
    
    info "Aguardando $service iniciar..."
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -s -o /dev/null -w "%{http_code}" "$url" | grep -q "200\|301\|302"; then
            info "$service está respondendo!"
            return 0
        fi
        
        debug "Tentativa $attempt/$max_attempts para $service"
        sleep 5
        ((attempt++))
    done
    
    error "$service não respondeu após $max_attempts tentativas"
    return 1
}

#-----------------------------------------------------------------------------
# Validações de sistema
#-----------------------------------------------------------------------------
check_system_requirements() {
    info "Verificando requisitos do sistema..."
    
    # Verificar se é root
    if [[ $EUID -ne 0 ]]; then
        error "Este script deve ser executado como root (use sudo)"
        exit 1
    fi
    
    # Verificar OS
    if ! grep -qi "ubuntu\|debian" /etc/os-release; then
        warn "Sistema não é Ubuntu/Debian. Continuando por sua conta e risco..."
    fi
    
    # Verificar memória
    local total_mem=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $total_mem -lt $MIN_MEMORY_GB ]]; then
        error "Memória insuficiente: ${total_mem}GB disponível, ${MIN_MEMORY_GB}GB necessário"
        exit 1
    fi
    
    # Verificar espaço em disco
    local available_disk=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $available_disk -lt $MIN_DISK_GB ]]; then
        error "Espaço em disco insuficiente: ${available_disk}GB disponível, ${MIN_DISK_GB}GB necessário"
        exit 1
    fi
    
    # Verificar portas
    for port in $CHATWOOT_PORT $WAHA_PORT $N8N_PORT 80 443; do
        if ! check_port "$port"; then
            error "Instalação abortada devido a conflito de portas"
            exit 1
        fi
    done
    
    info "Todos os requisitos do sistema foram atendidos ✓"
}

#-----------------------------------------------------------------------------
# Configuração interativa
#-----------------------------------------------------------------------------
interactive_setup() {
    if [[ "$INTERACTIVE" != "1" ]]; then
        return
    fi
    
    echo -e "\n${BLUE}=== Configuração do WNC Stack ===${NC}\n"
    
    # Seleção de componentes
    echo "Quais componentes deseja instalar?"
    read -p "Instalar Chatwoot? [S/n]: " -r
    [[ "$REPLY" =~ ^[Nn]$ ]] && INSTALL_CHATWOOT=0
    
    read -p "Instalar WAHA? [S/n]: " -r
    [[ "$REPLY" =~ ^[Nn]$ ]] && INSTALL_WAHA=0
    
    read -p "Instalar n8n? [S/n]: " -r
    [[ "$REPLY" =~ ^[Nn]$ ]] && INSTALL_N8N=0
    
    # Configuração de domínios
    if [[ -z "$CHAT_DOMAIN" ]] && [[ "$INSTALL_CHATWOOT" == "1" ]]; then
        read -p "Digite o domínio para Chatwoot (ex: chat.exemplo.com): " CHAT_DOMAIN
    fi
    
    if [[ -z "$WAHA_DOMAIN" ]] && [[ "$INSTALL_WAHA" == "1" ]]; then
        read -p "Digite o domínio para WAHA (ex: waha.exemplo.com): " WAHA_DOMAIN
    fi
    
    if [[ -z "$N8N_DOMAIN" ]] && [[ "$INSTALL_N8N" == "1" ]]; then
        read -p "Digite o domínio para n8n (ex: n8n.exemplo.com): " N8N_DOMAIN
    fi
    
    # Email para SSL
    if [[ -z "$EMAIL_SSL" ]]; then
        read -p "Digite o email para certificados SSL: " EMAIL_SSL
    fi
    
    # Validar email
    if ! [[ "$EMAIL_SSL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        error "Email inválido: $EMAIL_SSL"
        exit 1
    fi
    
    # Confirmar configurações
    echo -e "\n${YELLOW}=== Resumo da Configuração ===${NC}"
    [[ "$INSTALL_CHATWOOT" == "1" ]] && echo "Chatwoot: https://$CHAT_DOMAIN (porta $CHATWOOT_PORT)"
    [[ "$INSTALL_WAHA" == "1" ]] && echo "WAHA: https://$WAHA_DOMAIN (porta $WAHA_PORT)"
    [[ "$INSTALL_N8N" == "1" ]] && echo "n8n: https://$N8N_DOMAIN (porta $N8N_PORT)"
    echo "Email SSL: $EMAIL_SSL"
    echo
    
    read -p "Confirmar e prosseguir? [S/n]: " -r
    if [[ "$REPLY" =~ ^[Nn]$ ]]; then
        info "Instalação cancelada pelo usuário"
        exit 0
    fi
}

#-----------------------------------------------------------------------------
# Verificação de DNS
#-----------------------------------------------------------------------------
verify_dns() {
    local all_dns_ok=true
    
    info "Verificando configurações de DNS..."
    
    if [[ "$INSTALL_CHATWOOT" == "1" ]]; then
        check_domain_dns "$CHAT_DOMAIN" || all_dns_ok=false
    fi
    
    if [[ "$INSTALL_WAHA" == "1" ]]; then
        check_domain_dns "$WAHA_DOMAIN" || all_dns_ok=false
    fi
    
    if [[ "$INSTALL_N8N" == "1" ]]; then
        check_domain_dns "$N8N_DOMAIN" || all_dns_ok=false
    fi
    
    if [[ "$all_dns_ok" != "true" ]]; then
        echo
        warn "Alguns domínios não estão configurados corretamente no DNS"
        read -p "Deseja continuar mesmo assim? [s/N]: " -r
        if [[ ! "$REPLY" =~ ^[Ss]$ ]]; then
            info "Configure o DNS e execute novamente"
            exit 0
        fi
    fi
}

#-----------------------------------------------------------------------------
# Instalação de dependências
#-----------------------------------------------------------------------------
install_dependencies() {
    info "Atualizando sistema e instalando dependências..."
    
    apt-get update -qq
    apt_install curl wget gnupg lsb-release ca-certificates software-properties-common
    
    # Docker
    if ! cmd_exists docker; then
        info "Instalando Docker..."
        curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
        systemctl enable --now docker
    else
        info "Docker já instalado ✓"
    fi
    
    # Docker Compose Plugin
    apt_install docker-compose-plugin
    
    # Nginx + Certbot
    apt_install nginx certbot python3-certbot-nginx
    
    # Ferramentas adicionais
    apt_install jq htop net-tools dnsutils
}

#-----------------------------------------------------------------------------
# Configuração da rede Docker
#-----------------------------------------------------------------------------
setup_docker_network() {
    if ! docker network inspect "$STACK_NET" &>/dev/null; then
        info "Criando rede Docker $STACK_NET"
        docker network create "$STACK_NET"
    else
        info "Rede Docker $STACK_NET já existe ✓"
    fi
}

#-----------------------------------------------------------------------------
# Instalação do Chatwoot
#-----------------------------------------------------------------------------
install_chatwoot() {
    if [[ "$INSTALL_CHATWOOT" != "1" ]]; then
        return
    fi
    
    info "Instalando Chatwoot..."
    ensure_dir "/opt/chatwoot"
    
    local secret_key=$(openssl rand -hex 64)
    local pg_password=$(openssl rand -hex 32)
    
    # Salvar credenciais
    save_credential "CHATWOOT" "SECRET_KEY" "$secret_key"
    save_credential "CHATWOOT" "PG_PASSWORD" "$pg_password"
    save_credential "CHATWOOT" "URL" "https://$CHAT_DOMAIN"
    
    write_config /opt/chatwoot/.env <<EOF
NODE_ENV=production
RAILS_ENV=production
INSTALLATION_ENV=docker
SECRET_KEY_BASE=$secret_key
FRONTEND_URL=https://${CHAT_DOMAIN}
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_USER=chatwoot
POSTGRES_USERNAME=chatwoot
POSTGRES_PASSWORD=$pg_password
POSTGRES_DB=chatwoot
REDIS_URL=redis://redis:6379/0
ENABLE_ACCOUNT_SIGNUP=false
DEFAULT_LOCALE=pt_BR
FORCE_SSL=true
LOG_LEVEL=info
RAILS_MAX_THREADS=5
EOF

    write_config /opt/chatwoot/redis.conf <<'EOF'
# Redis configuration
appendonly yes
appendfsync everysec
save 900 1
save 300 10
save 60 10000
maxmemory-policy allkeys-lru
EOF

    write_config /opt/chatwoot/docker-compose.yml <<EOF
version: "3.8"

services:
  rails:
    image: chatwoot/chatwoot:latest
    env_file: .env
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    entrypoint: docker/entrypoints/rails.sh
    command: ["bundle", "exec", "rails", "s", "-p", "3000", "-b", "0.0.0.0"]
    networks: [$STACK_NET]
    ports: ["${CHATWOOT_PORT}:3000"]
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      
  sidekiq:
    image: chatwoot/chatwoot:latest
    env_file: .env
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    entrypoint: docker/entrypoints/rails.sh
    command: ["bundle", "exec", "sidekiq", "-C", "config/sidekiq.yml"]
    networks: [$STACK_NET]
    restart: unless-stopped
    
  postgres:
    image: pgvector/pgvector:pg15
    environment:
      POSTGRES_USER: chatwoot
      POSTGRES_PASSWORD: $pg_password
      POSTGRES_DB: chatwoot
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes: 
      - pg_data:/var/lib/postgresql/data
    networks: [$STACK_NET]
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U chatwoot"]
      interval: 10s
      timeout: 5s
      retries: 5
      
  redis:
    image: redis:7-alpine
    command: ["redis-server", "/usr/local/etc/redis/redis.conf"]
    volumes:
      - ./redis.conf:/usr/local/etc/redis/redis.conf:ro
      - redis_data:/data
    networks: [$STACK_NET]
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  $STACK_NET:
    external: true

volumes:
  pg_data:
  redis_data:
EOF

    CREATED_RESOURCES+=("docker:/opt/chatwoot/docker-compose.yml")
    
    docker compose -f /opt/chatwoot/docker-compose.yml up -d
    
    # Aguardar serviços ficarem prontos
    info "Aguardando serviços do Chatwoot..."
    sleep 20
    
    # Preparar banco de dados
    info "Preparando banco de dados do Chatwoot..."
    docker compose -f /opt/chatwoot/docker-compose.yml run --rm rails bundle exec rails db:chatwoot_prepare
    
    info "Chatwoot instalado com sucesso ✓"
}

#-----------------------------------------------------------------------------
# Instalação do WAHA
#-----------------------------------------------------------------------------
install_waha() {
    if [[ "$INSTALL_WAHA" != "1" ]]; then
        return
    fi
    
    info "Instalando WAHA..."
    ensure_dir "/opt/waha"
    
    local api_key=$(openssl rand -hex 32)
    local dash_pass=$(openssl rand -hex 16)
    local swagger_pass=$(openssl rand -hex 16)
    
    # Salvar credenciais
    save_credential "WAHA" "API_KEY" "$api_key"
    save_credential "WAHA" "DASHBOARD_USER" "admin"
    save_credential "WAHA" "DASHBOARD_PASSWORD" "$dash_pass"
    save_credential "WAHA" "SWAGGER_USER" "api"
    save_credential "WAHA" "SWAGGER_PASSWORD" "$swagger_pass"
    save_credential "WAHA" "URL" "https://$WAHA_DOMAIN"
    
    write_config /opt/waha/.env <<EOF
# WAHA Configuration
WHATSAPP_API_KEY=$api_key
WAHA_BASE_URL=https://${WAHA_DOMAIN}
WAHA_DASHBOARD_ENABLED=true
WAHA_DASHBOARD_USERNAME=admin
WAHA_DASHBOARD_PASSWORD=$dash_pass
WHATSAPP_SWAGGER_ENABLED=true
WHATSAPP_SWAGGER_USERNAME=api
WHATSAPP_SWAGGER_PASSWORD=$swagger_pass
WHATSAPP_RESTART_ALL_SESSIONS=true
WHATSAPP_START_SESSION=default
WAHA_WORKER_THREADS=10
WAHA_MESSAGES_LIFETIME=180d
EOF

    write_config /opt/waha/docker-compose.yml <<EOF
version: "3.8"

services:
  waha:
    image: devlikeapro/whatsapp-http-api:latest
    env_file: .env
    volumes: 
      - sessions:/app/.sessions
      - media:/app/.media
    ports: ["${WAHA_PORT}:3000"]
    networks: [$STACK_NET]
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  $STACK_NET:
    external: true

volumes:
  sessions:
  media:
EOF

    CREATED_RESOURCES+=("docker:/opt/waha/docker-compose.yml")
    
    docker compose -f /opt/waha/docker-compose.yml up -d
    
    info "WAHA instalado com sucesso ✓"
}

#-----------------------------------------------------------------------------
# Instalação do n8n
#-----------------------------------------------------------------------------
install_n8n() {
    if [[ "$INSTALL_N8N" != "1" ]]; then
        return
    fi
    
    info "Instalando n8n..."
    ensure_dir "/opt/n8n"
    
    local basic_user="admin"
    local basic_pass=$(openssl rand -hex 16)
    local encryption_key=$(openssl rand -hex 32)
    
    # Salvar credenciais
    save_credential "N8N" "BASIC_AUTH_USER" "$basic_user"
    save_credential "N8N" "BASIC_AUTH_PASSWORD" "$basic_pass"
    save_credential "N8N" "ENCRYPTION_KEY" "$encryption_key"
    save_credential "N8N" "URL" "https://$N8N_DOMAIN"
    
    write_config /opt/n8n/.env <<EOF
# n8n Configuration
N8N_HOST=${N8N_DOMAIN}
N8N_PORT=5678
N8N_PROTOCOL=https
WEBHOOK_URL=https://${N8N_DOMAIN}
N8N_SECURE_COOKIE=true
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=$basic_user
N8N_BASIC_AUTH_PASSWORD=$basic_pass
N8N_ENCRYPTION_KEY=$encryption_key
EXECUTIONS_DATA_PRUNE=true
EXECUTIONS_DATA_MAX_AGE=336
N8N_DIAGNOSTICS_ENABLED=false
N8N_VERSION_NOTIFICATIONS_ENABLED=true
N8N_METRICS=true
EOF

    write_config /opt/n8n/docker-compose.yml <<EOF
version: "3.8"

services:
  n8n:
    image: n8nio/n8n:latest
    env_file: .env
    environment:
      - NODE_ENV=production
    volumes: 
      - n8n_data:/home/node/.n8n
      - n8n_files:/files
    ports: ["${N8N_PORT}:5678"]
    networks: [$STACK_NET]
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  $STACK_NET:
    external: true

volumes:
  n8n_data:
  n8n_files:
EOF

    CREATED_RESOURCES+=("docker:/opt/n8n/docker-compose.yml")
    
    docker compose -f /opt/n8n/docker-compose.yml up -d
    
    info "n8n instalado com sucesso ✓"
}

#-----------------------------------------------------------------------------
# Configuração do Nginx
#-----------------------------------------------------------------------------
configure_nginx() {
    info "Configurando Nginx..."
    
    # Criar configuração base do Nginx
    write_config /etc/nginx/conf.d/security.conf <<'EOF'
# Security headers
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "no-referrer-when-downgrade" always;
add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline' 'unsafe-eval'" always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

# Hide Nginx version
server_tokens off;

# Buffer size
client_body_buffer_size 1K;
client_header_buffer_size 1k;
large_client_header_buffers 2 1k;

# Timeouts
client_body_timeout 10;
client_header_timeout 10;
keepalive_timeout 5 5;
send_timeout 10;

# Rate limiting zones
limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=api:10m rate=30r/s;
EOF

    # Função para criar vhost
    create_nginx_vhost() {
        local domain=$1
        local port=$2
        local app_name=$3
        
        write_config "/etc/nginx/sites-available/${domain}" <<EOF
# Rate limiting map
map \$request_uri \$limit_zone {
    ~^/api  api;
    default general;
}

server {
    listen 80;
    server_name ${domain};
    
    # Rate limiting
    limit_req zone=\$limit_zone burst=20 nodelay;
    
    # Logging
    access_log /var/log/nginx/${domain}_access.log;
    error_log /var/log/nginx/${domain}_error.log;
    
    location / {
        proxy_pass http://127.0.0.1:${port};
        proxy_http_version 1.1;
        
        # WebSocket support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Headers
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffering
        proxy_buffering off;
        proxy_request_buffering off;
        
        # Max body size (para uploads)
        client_max_body_size 100M;
    }
    
    # Health check endpoint
    location /nginx-health {
        access_log off;
        return 200 "healthy\\n";
        add_header Content-Type text/plain;
    }
}
EOF

        ln -sf "/etc/nginx/sites-available/${domain}" "/etc/nginx/sites-enabled/${domain}"
        CREATED_RESOURCES+=("nginx:${domain}")
    }
    
    # Criar vhosts para cada serviço
    [[ "$INSTALL_CHATWOOT" == "1" ]] && create_nginx_vhost "$CHAT_DOMAIN" "$CHATWOOT_PORT" "chatwoot"
    [[ "$INSTALL_WAHA" == "1" ]] && create_nginx_vhost "$WAHA_DOMAIN" "$WAHA_PORT" "waha"
    [[ "$INSTALL_N8N" == "1" ]] && create_nginx_vhost "$N8N_DOMAIN" "$N8N_PORT" "n8n"
    
    # Testar e recarregar Nginx
    nginx -t && systemctl reload nginx
    
    info "Nginx configurado com sucesso ✓"
}

#-----------------------------------------------------------------------------
# Configuração SSL
#-----------------------------------------------------------------------------
configure_ssl() {
    info "Configurando certificados SSL..."
    
    # Função para obter certificado
    get_ssl_cert() {
        local domain=$1
        
        info "Obtendo certificado SSL para $domain..."
        
        certbot --nginx \
            --non-interactive \
            --agree-tos \
            --no-eff-email \
            --email "$EMAIL_SSL" \
            --domains "$domain" \
            --redirect \
            --hsts \
            --staple-ocsp \
            --must-staple \
            --deploy-hook "systemctl reload nginx" \
            2>&1 | tee -a "$LOG_FILE"
            
        if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
            info "Certificado SSL obtido para $domain ✓"
            return 0
        else
            error "Falha ao obter certificado SSL para $domain"
            return 1
        fi
    }
    
    # Obter certificados para cada domínio
    local ssl_failed=0
    
    [[ "$INSTALL_CHATWOOT" == "1" ]] && ! get_ssl_cert "$CHAT_DOMAIN" && ((ssl_failed++))
    [[ "$INSTALL_WAHA" == "1" ]] && ! get_ssl_cert "$WAHA_DOMAIN" && ((ssl_failed++))
    [[ "$INSTALL_N8N" == "1" ]] && ! get_ssl_cert "$N8N_DOMAIN" && ((ssl_failed++))
    
    if [[ $ssl_failed -gt 0 ]]; then
        warn "Alguns certificados SSL falharam. Verifique os logs em $LOG_FILE"
    fi
    
    # Configurar renovação automática
    local cron_file="/etc/cron.d/certbot_renew_wnc"
    write_config "$cron_file" <<'EOF'
# Renovação automática de certificados SSL para WNC
0 2 * * * root certbot renew --quiet --deploy-hook 'systemctl reload nginx' >> /var/log/certbot-renew.log 2>&1
EOF
    
    chmod 644 "$cron_file"
    info "Renovação automática de SSL configurada ✓"
}

#-----------------------------------------------------------------------------
# Verificação de saúde
#-----------------------------------------------------------------------------
health_check() {
    info "Verificando saúde dos serviços..."
    
    local all_healthy=true
    
    # Verificar Chatwoot
    if [[ "$INSTALL_CHATWOOT" == "1" ]]; then
        if wait_for_service "Chatwoot" "http://localhost:$CHATWOOT_PORT/api/v1/health"; then
            info "Chatwoot: ✓ Saudável"
        else
            error "Chatwoot: ✗ Não respondendo"
            all_healthy=false
        fi
    fi
    
    # Verificar WAHA
    if [[ "$INSTALL_WAHA" == "1" ]]; then
        if wait_for_service "WAHA" "http://localhost:$WAHA_PORT/api/health"; then
            info "WAHA: ✓ Saudável"
        else
            error "WAHA: ✗ Não respondendo"
            all_healthy=false
        fi
    fi
    
    # Verificar n8n
    if [[ "$INSTALL_N8N" == "1" ]]; then
        if wait_for_service "n8n" "http://localhost:$N8N_PORT/healthz"; then
            info "n8n: ✓ Saudável"
        else
            error "n8n: ✗ Não respondendo"
            all_healthy=false
        fi
    fi
    
    # Verificar Nginx
    if systemctl is-active --quiet nginx; then
        info "Nginx: ✓ Ativo"
    else
        error "Nginx: ✗ Inativo"
        all_healthy=false
    fi
    
    return $([[ "$all_healthy" == "true" ]] && echo 0 || echo 1)
}

#-----------------------------------------------------------------------------
# Configuração de firewall
#-----------------------------------------------------------------------------
configure_firewall() {
    if ! cmd_exists ufw; then
        info "Instalando UFW..."
        apt_install ufw
    fi
    
    info "Configurando firewall..."
    
    # Regras básicas
    ufw --force disable
    ufw default deny incoming
    ufw default allow outgoing
    
    # Permitir SSH
    ufw allow 22/tcp comment "SSH"
    
    # Permitir HTTP/HTTPS
    ufw allow 80/tcp comment "HTTP"
    ufw allow 443/tcp comment "HTTPS"
    
    # Permitir portas dos serviços (apenas localhost)
    # As portas dos serviços não precisam ser abertas externamente
    # pois o Nginx faz o proxy
    
    # Habilitar firewall
    ufw --force enable
    
    info "Firewall configurado ✓"
}

#-----------------------------------------------------------------------------
# Criação de scripts auxiliares
#-----------------------------------------------------------------------------
create_helper_scripts() {
    info "Criando scripts auxiliares..."
    
    # Script de status
    write_config /usr/local/bin/wnc-status <<'EOF'
#!/bin/bash
echo "=== Status dos Serviços WNC ==="
echo

# Chatwoot
if [[ -d /opt/chatwoot ]]; then
    echo "Chatwoot:"
    docker compose -f /opt/chatwoot/docker-compose.yml ps
    echo
fi

# WAHA
if [[ -d /opt/waha ]]; then
    echo "WAHA:"
    docker compose -f /opt/waha/docker-compose.yml ps
    echo
fi

# n8n
if [[ -d /opt/n8n ]]; then
    echo "n8n:"
    docker compose -f /opt/n8n/docker-compose.yml ps
    echo
fi

# Nginx
echo "Nginx:"
systemctl status nginx --no-pager | head -n 3
EOF
    
    # Script de logs
    write_config /usr/local/bin/wnc-logs <<'EOF'
#!/bin/bash
service=${1:-all}

case "$service" in
    chatwoot)
        docker compose -f /opt/chatwoot/docker-compose.yml logs -f
        ;;
    waha)
        docker compose -f /opt/waha/docker-compose.yml logs -f
        ;;
    n8n)
        docker compose -f /opt/n8n/docker-compose.yml logs -f
        ;;
    nginx)
        tail -f /var/log/nginx/*.log
        ;;
    all)
        echo "Use: wnc-logs [chatwoot|waha|n8n|nginx]"
        ;;
esac
EOF
    
    # Script de restart
    write_config /usr/local/bin/wnc-restart <<'EOF'
#!/bin/bash
service=${1:-all}

restart_service() {
    local name=$1
    local compose_file=$2
    
    echo "Reiniciando $name..."
    docker compose -f "$compose_file" restart
}

case "$service" in
    chatwoot)
        restart_service "Chatwoot" "/opt/chatwoot/docker-compose.yml"
        ;;
    waha)
        restart_service "WAHA" "/opt/waha/docker-compose.yml"
        ;;
    n8n)
        restart_service "n8n" "/opt/n8n/docker-compose.yml"
        ;;
    nginx)
        echo "Reiniciando Nginx..."
        systemctl restart nginx
        ;;
    all)
        [[ -d /opt/chatwoot ]] && restart_service "Chatwoot" "/opt/chatwoot/docker-compose.yml"
        [[ -d /opt/waha ]] && restart_service "WAHA" "/opt/waha/docker-compose.yml"
        [[ -d /opt/n8n ]] && restart_service "n8n" "/opt/n8n/docker-compose.yml"
        systemctl restart nginx
        ;;
    *)
        echo "Use: wnc-restart [chatwoot|waha|n8n|nginx|all]"
        ;;
esac
EOF
    
    # Tornar scripts executáveis
    chmod +x /usr/local/bin/wnc-*
    
    info "Scripts auxiliares criados ✓"
}

#-----------------------------------------------------------------------------
# Exibir informações finais
#-----------------------------------------------------------------------------
show_summary() {
    echo
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           Instalação Concluída com Sucesso! 🎉             ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    echo -e "${BLUE}URLs dos Serviços:${NC}"
    [[ "$INSTALL_CHATWOOT" == "1" ]] && echo " • Chatwoot: https://$CHAT_DOMAIN"
    [[ "$INSTALL_WAHA" == "1" ]] && echo " • WAHA:     https://$WAHA_DOMAIN"
    [[ "$INSTALL_N8N" == "1" ]] && echo " • n8n:      https://$N8N_DOMAIN"
    echo
    
    echo -e "${BLUE}Credenciais salvas em:${NC} $CREDENTIALS_FILE"
    echo
    
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        echo -e "${YELLOW}Credenciais de Acesso:${NC}"
        
        if [[ "$INSTALL_CHATWOOT" == "1" ]]; then
            echo -e "\n${GREEN}Chatwoot:${NC}"
            echo " • URL: https://$CHAT_DOMAIN"
            echo " • Criar conta admin: https://$CHAT_DOMAIN/super_admin"
        fi
        
        if [[ "$INSTALL_WAHA" == "1" ]]; then
            echo -e "\n${GREEN}WAHA:${NC}"
            grep "^WAHA_" "$CREDENTIALS_FILE" | sed 's/WAHA_/ • /' | sed 's/=/:/'
        fi
        
        if [[ "$INSTALL_N8N" == "1" ]]; then
            echo -e "\n${GREEN}n8n:${NC}"
            grep "^N8N_" "$CREDENTIALS_FILE" | sed 's/N8N_/ • /' | sed 's/=/:/'
        fi
    fi
    
    echo
    echo -e "${BLUE}Comandos úteis:${NC}"
    echo " • wnc-status  - Ver status dos serviços"
    echo " • wnc-logs    - Ver logs dos serviços"
    echo " • wnc-restart - Reiniciar serviços"
    echo
    
    echo -e "${YELLOW}Próximos passos:${NC}"
    echo " 1. Configure o super admin do Chatwoot"
    echo " 2. Escaneie o QR code no WAHA para conectar WhatsApp"
    echo " 3. Configure os workflows no n8n"
    echo " 4. Integre os serviços conforme necessário"
    echo
    
    echo -e "${GREEN}Log completo em:${NC} $LOG_FILE"
    echo
}

#-----------------------------------------------------------------------------
# Função principal
#-----------------------------------------------------------------------------
main() {
    clear
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              WNC Stack Auto-Installer v2.0                 ║"
    echo "║           Chatwoot + WAHA + n8n com Nginx/SSL            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Verificar requisitos
    check_system_requirements
    
    # Configuração interativa
    interactive_setup
    
    # Verificar DNS
    verify_dns
    
    # Instalação
    install_dependencies
    setup_docker_network
    
    # Instalar serviços
    install_chatwoot
    install_waha
    install_n8n
    
    # Configurar proxy e SSL
    configure_nginx
    configure_ssl
    
    # Configurações adicionais
    configure_firewall
    create_helper_scripts
    
    # Verificação final
    if health_check; then
        show_summary
        info "Instalação concluída com sucesso!"
        exit 0
    else
        error "Alguns serviços não estão funcionando corretamente"
        error "Verifique os logs para mais detalhes"
        exit 1
    fi
}

# Executar função principal
main "$@"
