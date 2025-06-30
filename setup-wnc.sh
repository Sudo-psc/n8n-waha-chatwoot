#!/usr/bin/env bash
###############################################################################
#  Auto-installer: Chatwoot + WAHA + n8n (Docker) com Nginx e HTTPS
#  Versão: 2.0 - Revisada e Melhorada
#  Autor: philipe_cruz@outlook.com
###############################################################################

# Structured logging ----------------------------------------------------------
SCRIPT_NAME=$(basename "$0" .sh)
SCRIPT_VERSION="2.0"
LOG_FILE="/var/log/${SCRIPT_NAME}.log"
CREDENTIALS_FILE="/root/.wnc-credentials"
DEBUG_MODE=${DEBUG:-false}

# Cores para output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuração de logging
mkdir -p "$(dirname "$LOG_FILE")" && touch "$LOG_FILE"
log() { 
    local level="$1"; shift
    local msg="$(date '+%F %T') [$level] $*"
    echo "$msg" >> "$LOG_FILE"
    case "$level" in
        INFO)  echo -e "${BLUE}[INFO]${NC} $*" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $*" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $*" ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $*" ;;
        DEBUG) [[ "$DEBUG_MODE" == "true" ]] && echo -e "[DEBUG] $*" ;;
    esac
}
info() { log INFO "$@"; }
warn() { log WARN "$@"; }
error() { log ERROR "$@"; }
success() { log SUCCESS "$@"; }
debug() { log DEBUG "$@"; }

# Configuração de erro handling
set -Eeuo pipefail
ROLLBACK_POINTS=()
trap 'handle_error $? $LINENO "$BASH_COMMAND"' ERR
trap 'handle_exit' EXIT

handle_error() {
    local exit_code=$1
    local line_no=$2
    local bash_command=$3
    error "Erro na linha $line_no: comando '$bash_command' falhou com código $exit_code"
    
    if [[ ${#ROLLBACK_POINTS[@]} -gt 0 ]]; then
        warn "Iniciando rollback..."
        for point in "${ROLLBACK_POINTS[@]}"; do
            debug "Executando rollback: $point"
            eval "$point" || true
        done
    fi
    exit $exit_code
}

handle_exit() {
    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        success "Script finalizado com sucesso"
    else
        error "Script finalizado com erros (código: $exit_code)"
    fi
}

# Valores padrão (podem ser sobrescritos)
DEFAULT_CHAT_DOMAIN="chat.example.com"
DEFAULT_WAHA_DOMAIN="waha.example.com"
DEFAULT_N8N_DOMAIN="n8n.example.com"
DEFAULT_EMAIL="admin@example.com"
STACK_NET="wcn_net"

# Variáveis globais
CHAT_DOMAIN=""
WAHA_DOMAIN=""
N8N_DOMAIN=""
EMAIL_SSL=""
INSTALL_COMPONENTS=()
SKIP_DNS_CHECK=false
SKIP_CERT_GENERATION=false
DRY_RUN=false

#-----------------------------------------------------------------------------
# Funções utilitárias
#-----------------------------------------------------------------------------
apt_install() {
    debug "Instalando pacotes: $*"
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" >/dev/null 2>&1 || {
        error "Falha ao instalar pacotes: $*"
        return 1
    }
}

cmd_exists() { 
    command -v "$1" &>/dev/null 
}

# Cria diretório se não existir
ensure_dir() {
    local dir=$1
    if [[ -d $dir ]]; then
        debug "Diretório $dir já existe"
    else
        mkdir -p "$dir"
        chmod 755 "$dir"
        debug "Diretório $dir criado"
    fi
}

# Faz backup de arquivo existente e grava conteúdo
write_config() {
    local file=$1
    shift
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Escreveria arquivo: $file"
        return
    fi
    
    if [[ -f $file ]]; then
        local bk="${file}.bak.$(date +%s)"
        cp "$file" "$bk"
        debug "Backup de $file criado em $bk"
        ROLLBACK_POINTS+=("mv '$bk' '$file'")
    fi
    
    cat > "$file" "$@"
    debug "Arquivo $file escrito"
}

# Salva credenciais de forma segura
save_credentials() {
    local service=$1
    local key=$2
    local value=$3
    
    # Cria arquivo se não existir
    if [[ ! -f "$CREDENTIALS_FILE" ]]; then
        touch "$CREDENTIALS_FILE"
        chmod 600 "$CREDENTIALS_FILE"
    fi
    
    # Adiciona ou atualiza credencial
    if grep -q "^${service}_${key}=" "$CREDENTIALS_FILE" 2>/dev/null; then
        sed -i "s|^${service}_${key}=.*|${service}_${key}=${value}|" "$CREDENTIALS_FILE"
    else
        echo "${service}_${key}=${value}" >> "$CREDENTIALS_FILE"
    fi
}

# Função para mostrar progresso
show_progress() {
    local current=$1
    local total=$2
    local task=$3
    local percent=$((current * 100 / total))
    printf "\r[%-50s] %d%% - %s" "$(printf '#%.0s' $(seq 1 $((percent / 2))))" "$percent" "$task"
    [[ $current -eq $total ]] && echo
}

#-----------------------------------------------------------------------------
# Validações e pré-requisitos
#-----------------------------------------------------------------------------
check_prerequisites() {
    info "Verificando pré-requisitos..."
    
    # Verifica se é root
    [[ $EUID -eq 0 ]] || { error "Execute como root (sudo)"; exit 1; }
    
    # Verifica sistema operacional
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "$ID" != "ubuntu" ]] && [[ "$ID" != "debian" ]]; then
            warn "Sistema não é Ubuntu/Debian. Continuando por sua conta e risco..."
        fi
    fi
    
    # Verifica espaço em disco (mínimo 10GB)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 10485760 ]]; then
        error "Espaço em disco insuficiente. Necessário pelo menos 10GB livres."
        exit 1
    fi
    
    # Verifica memória RAM (mínimo 2GB)
    local total_mem=$(free -m | awk 'NR==2 {print $2}')
    if [[ $total_mem -lt 2048 ]]; then
        warn "Memória RAM abaixo do recomendado (2GB). Performance pode ser afetada."
    fi
    
    # Verifica conectividade
    if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        error "Sem conectividade com a internet"
        exit 1
    fi
    
    success "Pré-requisitos verificados"
}

check_ports() {
    info "Verificando portas necessárias..."
    local ports=(80 443 3000 3001 3002 5432 6379 5678)
    local used_ports=()
    
    for port in "${ports[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            used_ports+=($port)
        fi
    done
    
    if [[ ${#used_ports[@]} -gt 0 ]]; then
        warn "As seguintes portas já estão em uso: ${used_ports[*]}"
        warn "Isso pode causar conflitos. Deseja continuar? (s/N)"
        read -r response
        [[ "$response" =~ ^[Ss]$ ]] || exit 1
    fi
    
    success "Verificação de portas concluída"
}

validate_dns() {
    local domain=$1
    
    if [[ "$SKIP_DNS_CHECK" == "true" ]]; then
        debug "Pulando verificação DNS para $domain"
        return 0
    fi
    
    info "Verificando DNS para $domain..."
    
    # Verifica se o domínio resolve
    if ! host "$domain" &>/dev/null; then
        error "Domínio $domain não resolve. Verifique suas configurações DNS."
        return 1
    fi
    
    # Verifica se aponta para este servidor
    local domain_ip=$(dig +short "$domain" | tail -n1)
    local server_ip=$(curl -s ifconfig.me)
    
    if [[ "$domain_ip" != "$server_ip" ]]; then
        warn "Domínio $domain aponta para $domain_ip, mas este servidor é $server_ip"
        warn "Certifique-se de que o DNS está configurado corretamente."
        warn "Continuar mesmo assim? (s/N)"
        read -r response
        [[ "$response" =~ ^[Ss]$ ]] || return 1
    fi
    
    success "DNS válido para $domain"
    return 0
}

#-----------------------------------------------------------------------------
# Interface interativa
#-----------------------------------------------------------------------------
show_banner() {
    cat << 'BANNER'
    __        ___   _  ____       ____ _     ___ 
    \ \      / / \ | |/ ___|     / ___| |   |_ _|
     \ \ /\ / /|  \| | |   _____| |   | |    | | 
      \ V  V / | |\  | |__|_____| |___| |___ | | 
       \_/\_/  |_| \_|\____|     \____|_____|___|
    
    Chatwoot + WAHA + n8n - Auto Installer v2.0
BANNER
}

interactive_setup() {
    show_banner
    echo
    info "Modo de configuração interativa"
    echo
    
    # Seleção de componentes
    echo "Quais componentes deseja instalar?"
    echo "1) Todos (Chatwoot + WAHA + n8n)"
    echo "2) Apenas Chatwoot"
    echo "3) Apenas WAHA"
    echo "4) Apenas n8n"
    echo "5) Personalizado"
    read -p "Escolha [1-5]: " choice
    
    case $choice in
        1) INSTALL_COMPONENTS=(chatwoot waha n8n) ;;
        2) INSTALL_COMPONENTS=(chatwoot) ;;
        3) INSTALL_COMPONENTS=(waha) ;;
        4) INSTALL_COMPONENTS=(n8n) ;;
        5) 
            echo "Selecione os componentes (separados por espaço):"
            echo "Opções: chatwoot waha n8n"
            read -p "Componentes: " -a INSTALL_COMPONENTS
            ;;
        *) error "Opção inválida"; exit 1 ;;
    esac
    
    # Configuração de domínios
    echo
    if [[ " ${INSTALL_COMPONENTS[@]} " =~ " chatwoot " ]]; then
        read -p "Domínio para Chatwoot [$DEFAULT_CHAT_DOMAIN]: " CHAT_DOMAIN
        CHAT_DOMAIN=${CHAT_DOMAIN:-$DEFAULT_CHAT_DOMAIN}
    fi
    
    if [[ " ${INSTALL_COMPONENTS[@]} " =~ " waha " ]]; then
        read -p "Domínio para WAHA [$DEFAULT_WAHA_DOMAIN]: " WAHA_DOMAIN
        WAHA_DOMAIN=${WAHA_DOMAIN:-$DEFAULT_WAHA_DOMAIN}
    fi
    
    if [[ " ${INSTALL_COMPONENTS[@]} " =~ " n8n " ]]; then
        read -p "Domínio para n8n [$DEFAULT_N8N_DOMAIN]: " N8N_DOMAIN
        N8N_DOMAIN=${N8N_DOMAIN:-$DEFAULT_N8N_DOMAIN}
    fi
    
    # Email para SSL
    read -p "Email para certificados SSL [$DEFAULT_EMAIL]: " EMAIL_SSL
    EMAIL_SSL=${EMAIL_SSL:-$DEFAULT_EMAIL}
    
    # Opções avançadas
    echo
    echo "Configurações avançadas (pressione Enter para padrão):"
    read -p "Pular verificação de DNS? (s/N): " skip_dns
    [[ "$skip_dns" =~ ^[Ss]$ ]] && SKIP_DNS_CHECK=true
    
    read -p "Pular geração de certificados SSL? (s/N): " skip_cert
    [[ "$skip_cert" =~ ^[Ss]$ ]] && SKIP_CERT_GENERATION=true
    
    # Confirmação
    echo
    echo "=== Resumo da Configuração ==="
    echo "Componentes: ${INSTALL_COMPONENTS[*]}"
    [[ " ${INSTALL_COMPONENTS[@]} " =~ " chatwoot " ]] && echo "Chatwoot: https://$CHAT_DOMAIN"
    [[ " ${INSTALL_COMPONENTS[@]} " =~ " waha " ]] && echo "WAHA: https://$WAHA_DOMAIN"
    [[ " ${INSTALL_COMPONENTS[@]} " =~ " n8n " ]] && echo "n8n: https://$N8N_DOMAIN"
    echo "Email SSL: $EMAIL_SSL"
    echo "=============================="
    echo
    read -p "Confirma instalação? (s/N): " confirm
    [[ "$confirm" =~ ^[Ss]$ ]] || exit 0
}

#-----------------------------------------------------------------------------
# Instalação de componentes base
#-----------------------------------------------------------------------------
install_docker() {
    if cmd_exists docker; then
        info "Docker já instalado - verificando versão..."
        docker --version
    else
        info "Instalando Docker Engine..."
        curl -fsSL https://get.docker.com | sh
        ROLLBACK_POINTS+=("apt-get remove -y docker-ce docker-ce-cli containerd.io")
    fi
    
    apt_install docker-compose-plugin
    systemctl enable --now docker
    
    # Adiciona usuário atual ao grupo docker
    if [[ -n "${SUDO_USER:-}" ]]; then
        usermod -aG docker "$SUDO_USER"
    fi
    
    success "Docker instalado e configurado"
}

install_nginx() {
    info "Instalando Nginx e Certbot..."
    apt_install nginx certbot python3-certbot-nginx
    
    # Configuração básica de segurança do Nginx
    write_config /etc/nginx/conf.d/security.conf <<'EOF'
# Segurança básica
server_tokens off;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "no-referrer-when-downgrade" always;

# Limite de tamanho de requisição
client_max_body_size 100M;
client_body_timeout 60;
client_header_timeout 60;
keepalive_timeout 65;
send_timeout 60;

# Limite de rate
limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=api:10m rate=30r/s;
EOF
    
    systemctl enable --now nginx
    success "Nginx instalado e configurado"
}

create_docker_network() {
    if ! docker network inspect $STACK_NET &>/dev/null; then
        info "Criando rede Docker $STACK_NET..."
        docker network create "$STACK_NET"
        ROLLBACK_POINTS+=("docker network rm $STACK_NET")
    else
        debug "Rede $STACK_NET já existe"
    fi
}

#-----------------------------------------------------------------------------
# Instalação do Chatwoot
#-----------------------------------------------------------------------------
install_chatwoot() {
    info "Instalando Chatwoot..."
    ensure_dir /opt/chatwoot
    
    # Gera credenciais
    local secret_key=$(openssl rand -hex 64)
    local pg_password=$(openssl rand -hex 16)
    
    # Salva credenciais
    save_credentials "chatwoot" "secret_key" "$secret_key"
    save_credentials "chatwoot" "postgres_password" "$pg_password"
    save_credentials "chatwoot" "url" "https://$CHAT_DOMAIN"
    
    # Configuração do ambiente
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
RAILS_LOG_TO_STDOUT=true
LOG_LEVEL=info
ENABLE_ACCOUNT_SIGNUP=false
EOF
    
    # Configuração do Redis
    write_config /opt/chatwoot/redis.conf <<'EOF'
# Persistência
appendonly yes
save 900 1
save 300 10
save 60 10000

# Segurança
protected-mode yes
requirepass $(openssl rand -hex 16)

# Performance
maxmemory 256mb
maxmemory-policy allkeys-lru
EOF
    
    # Docker Compose
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
    ports: ["3000:3000"]
    volumes:
      - storage:/app/storage
    restart: always
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
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
    volumes:
      - storage:/app/storage
    restart: always

  postgres:
    image: pgvector/pgvector:pg15
    environment:
      POSTGRES_USER: chatwoot
      POSTGRES_PASSWORD: $pg_password
      POSTGRES_DB: chatwoot
    volumes: 
      - pg_data:/var/lib/postgresql/data
    networks: [$STACK_NET]
    restart: always
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
    restart: always
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
  storage:
EOF
    
    # Inicia containers
    info "Iniciando containers do Chatwoot..."
    docker compose -f /opt/chatwoot/docker-compose.yml up -d
    
    # Aguarda Postgres ficar pronto
    info "Aguardando banco de dados..."
    local attempts=0
    while ! docker compose -f /opt/chatwoot/docker-compose.yml exec -T postgres pg_isready -U chatwoot &>/dev/null; do
        ((attempts++))
        if [[ $attempts -gt 30 ]]; then
            error "Timeout aguardando Postgres"
            return 1
        fi
        sleep 2
    done
    
    # Prepara banco de dados
    info "Preparando banco de dados..."
    docker compose -f /opt/chatwoot/docker-compose.yml run --rm rails bundle exec rails db:chatwoot_prepare
    
    success "Chatwoot instalado com sucesso"
}

#-----------------------------------------------------------------------------
# Instalação do WAHA
#-----------------------------------------------------------------------------
install_waha() {
    info "Instalando WAHA..."
    ensure_dir /opt/waha
    
    # Gera credenciais
    local api_key=$(openssl rand -hex 32)
    local dash_pass=$(openssl rand -hex 12)
    local swagger_pass=$(openssl rand -hex 12)
    
    # Salva credenciais
    save_credentials "waha" "api_key" "$api_key"
    save_credentials "waha" "dashboard_user" "admin"
    save_credentials "waha" "dashboard_password" "$dash_pass"
    save_credentials "waha" "swagger_user" "api"
    save_credentials "waha" "swagger_password" "$swagger_pass"
    save_credentials "waha" "url" "https://$WAHA_DOMAIN"
    
    # Configuração
    write_config /opt/waha/.env <<EOF
# API Configuration
WHATSAPP_API_KEY=$api_key
WAHA_BASE_URL=https://${WAHA_DOMAIN}

# Dashboard Authentication
WAHA_DASHBOARD_USERNAME=admin
WAHA_DASHBOARD_PASSWORD=$dash_pass

# Swagger Authentication
WHATSAPP_SWAGGER_USERNAME=api
WHATSAPP_SWAGGER_PASSWORD=$swagger_pass

# Additional Settings
WHATSAPP_RESTART_ALL_SESSIONS=true
WHATSAPP_START_SESSION=default
WAHA_WORKER_THREADS=10
WAHA_WEBHOOK_RETRIES=3
WAHA_LOG_LEVEL=info
EOF
    
    # Docker Compose
    write_config /opt/waha/docker-compose.yml <<EOF
version: "3.8"
services:
  waha:
    image: devlikeapro/whatsapp-http-api:latest
    env_file: .env
    volumes:
      - sessions:/app/.sessions
      - media:/app/.media
    ports: ["3001:3000"]
    networks: [$STACK_NET]
    restart: always
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    deploy:
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 512M

networks:
  $STACK_NET:
    external: true

volumes:
  sessions:
  media:
EOF
    
    # Inicia container
    docker compose -f /opt/waha/docker-compose.yml up -d
    
    success "WAHA instalado com sucesso"
}

#-----------------------------------------------------------------------------
# Instalação do n8n
#-----------------------------------------------------------------------------
install_n8n() {
    info "Instalando n8n..."
    ensure_dir /opt/n8n
    
    # Gera credenciais
    local basic_auth_pass=$(openssl rand -hex 12)
    local encryption_key=$(openssl rand -hex 16)
    
    # Salva credenciais
    save_credentials "n8n" "user" "admin"
    save_credentials "n8n" "password" "$basic_auth_pass"
    save_credentials "n8n" "encryption_key" "$encryption_key"
    save_credentials "n8n" "url" "https://$N8N_DOMAIN"
    
    # Configuração
    write_config /opt/n8n/.env <<EOF
# n8n Configuration
N8N_HOST=${N8N_DOMAIN}
N8N_PORT=5678
N8N_PROTOCOL=https
WEBHOOK_URL=https://${N8N_DOMAIN}

# Authentication
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=$basic_auth_pass

# Security
N8N_ENCRYPTION_KEY=$encryption_key
N8N_SECURE_COOKIE=true

# Database
DB_TYPE=sqlite

# Execution
EXECUTIONS_PROCESS=main
N8N_PERSONALIZATION_ENABLED=false

# Logs
N8N_LOG_LEVEL=info
N8N_LOG_OUTPUT=console
EOF
    
    # Docker Compose
    write_config /opt/n8n/docker-compose.yml <<EOF
version: "3.8"
services:
  n8n:
    image: n8nio/n8n:latest
    env_file: .env
    volumes:
      - n8n_data:/home/node/.n8n
      - ./workflows:/home/node/.n8n/workflows
    ports: ["3002:5678"]
    networks: [$STACK_NET]
    restart: always
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5678/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 1G

networks:
  $STACK_NET:
    external: true

volumes:
  n8n_data:
EOF
    
    # Cria diretório para workflows
    ensure_dir /opt/n8n/workflows
    
    # Inicia container
    docker compose -f /opt/n8n/docker-compose.yml up -d
    
    success "n8n instalado com sucesso"
}

#-----------------------------------------------------------------------------
# Configuração do Nginx
#-----------------------------------------------------------------------------
configure_nginx() {
    info "Configurando Nginx..."
    
    # Template para virtual host
    create_vhost() {
        local domain=$1
        local port=$2
        local name=$3
        
        write_config "/etc/nginx/sites-available/${domain}" <<EOF
# Rate limiting
limit_req_zone \$binary_remote_addr zone=${name}_limit:10m rate=10r/s;

server {
    server_name ${domain};
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' https: data: 'unsafe-inline' 'unsafe-eval';" always;
    
    # Rate limiting
    limit_req zone=${name}_limit burst=20 nodelay;
    
    # Proxy settings
    location / {
        proxy_pass http://127.0.0.1:${port};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
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
        
        # Max body size
        client_max_body_size 100M;
    }
    
    # Health check endpoint
    location /nginx-health {
        access_log off;
        return 200 "healthy\\n";
        add_header Content-Type text/plain;
    }
    
    listen 80;
}
EOF
        
        ln -sf "/etc/nginx/sites-available/${domain}" "/etc/nginx/sites-enabled/${domain}"
        ROLLBACK_POINTS+=("rm -f /etc/nginx/sites-enabled/${domain}")
    }
    
    # Cria virtual hosts para cada componente
    [[ " ${INSTALL_COMPONENTS[@]} " =~ " chatwoot " ]] && create_vhost "$CHAT_DOMAIN" 3000 "chatwoot"
    [[ " ${INSTALL_COMPONENTS[@]} " =~ " waha " ]] && create_vhost "$WAHA_DOMAIN" 3001 "waha"
    [[ " ${INSTALL_COMPONENTS[@]} " =~ " n8n " ]] && create_vhost "$N8N_DOMAIN" 3002 "n8n"
    
    # Testa configuração
    if nginx -t; then
        systemctl reload nginx
        success "Nginx configurado com sucesso"
    else
        error "Erro na configuração do Nginx"
        return 1
    fi
}

#-----------------------------------------------------------------------------
# Certificados SSL
#-----------------------------------------------------------------------------
install_ssl_certificates() {
    if [[ "$SKIP_CERT_GENERATION" == "true" ]]; then
        warn "Pulando geração de certificados SSL"
        return 0
    fi
    
    info "Instalando certificados SSL..."
    
    # Função para instalar certificado
    install_cert() {
        local domain=$1
        info "Gerando certificado para $domain..."
        
        if certbot certonly --nginx \
            --non-interactive \
            --agree-tos \
            --no-eff-email \
            -m "$EMAIL_SSL" \
            -d "$domain" \
            --deploy-hook "systemctl reload nginx"; then
            
            # Atualiza configuração do Nginx para HTTPS
            sed -i "/listen 80;/a\\
    listen 443 ssl http2;\\
    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;\\
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;\\
    ssl_protocols TLSv1.2 TLSv1.3;\\
    ssl_ciphers HIGH:!aNULL:!MD5;\\
    ssl_prefer_server_ciphers on;\\
    \\
    # HTTP to HTTPS redirect\\
    if (\\\$scheme != \\\"https\\\") {\\
        return 301 https://\\\$server_name\\\$request_uri;\\
    }" "/etc/nginx/sites-available/${domain}"
            
            success "Certificado SSL instalado para $domain"
        else
            error "Falha ao gerar certificado para $domain"
            return 1
        fi
    }
    
    # Instala certificados para cada domínio
    [[ " ${INSTALL_COMPONENTS[@]} " =~ " chatwoot " ]] && install_cert "$CHAT_DOMAIN"
    [[ " ${INSTALL_COMPONENTS[@]} " =~ " waha " ]] && install_cert "$WAHA_DOMAIN"
    [[ " ${INSTALL_COMPONENTS[@]} " =~ " n8n " ]] && install_cert "$N8N_DOMAIN"
    
    # Configura renovação automática
    write_config /etc/systemd/system/certbot-renew.service <<'EOF'
[Unit]
Description=Certbot Renewal
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --quiet --deploy-hook "systemctl reload nginx"
EOF
    
    write_config /etc/systemd/system/certbot-renew.timer <<'EOF'
[Unit]
Description=Run certbot renewal twice daily

[Timer]
OnCalendar=*-*-* 00,12:00:00
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    systemctl daemon-reload
    systemctl enable --now certbot-renew.timer
    
    # Recarrega Nginx com nova configuração
    systemctl reload nginx
    
    success "Certificados SSL configurados com renovação automática"
}

#-----------------------------------------------------------------------------
# Testes e validação
#-----------------------------------------------------------------------------
test_installation() {
    info "Executando testes de validação..."
    local all_tests_passed=true
    
    # Testa cada serviço
    test_service() {
        local name=$1
        local url=$2
        local expected_code=$3
        
        info "Testando $name..."
        local code=$(curl -k -s -o /dev/null -w "%{http_code}" "$url" || echo "000")
        
        if [[ "$code" == "$expected_code" ]] || [[ "$code" == "401" ]] || [[ "$code" == "302" ]]; then
            success "$name respondendo corretamente (HTTP $code)"
            return 0
        else
            error "$name não está respondendo corretamente (HTTP $code)"
            all_tests_passed=false
            return 1
        fi
    }
    
    # Aguarda serviços iniciarem
    info "Aguardando serviços iniciarem..."
    sleep 10
    
    # Testa cada componente instalado
    if [[ " ${INSTALL_COMPONENTS[@]} " =~ " chatwoot " ]]; then
        test_service "Chatwoot" "https://$CHAT_DOMAIN/health" "200"
    fi
    
    if [[ " ${INSTALL_COMPONENTS[@]} " =~ " waha " ]]; then
        test_service "WAHA" "https://$WAHA_DOMAIN/health" "200"
    fi
    
    if [[ " ${INSTALL_COMPONENTS[@]} " =~ " n8n " ]]; then
        test_service "n8n" "https://$N8N_DOMAIN" "200"
    fi
    
    if [[ "$all_tests_passed" == "true" ]]; then
        success "Todos os testes passaram!"
        return 0
    else
        error "Alguns testes falharam. Verifique os logs."
        return 1
    fi
}

#-----------------------------------------------------------------------------
# Pós-instalação
#-----------------------------------------------------------------------------
show_credentials() {
    echo
    echo "==================================================================="
    echo "                    INSTALAÇÃO CONCLUÍDA!"
    echo "==================================================================="
    echo
    echo "Credenciais salvas em: $CREDENTIALS_FILE"
    echo
    
    if [[ " ${INSTALL_COMPONENTS[@]} " =~ " chatwoot " ]]; then
        echo "CHATWOOT:"
        echo "  URL: https://$CHAT_DOMAIN"
        echo "  Criar conta admin: docker compose -f /opt/chatwoot/docker-compose.yml run --rm rails bundle exec rails c"
        echo "  No console Rails: User.create!(name: 'Admin', email: 'admin@example.com', password: 'senha123', confirmed_at: Time.now)"
        echo
    fi
    
    if [[ " ${INSTALL_COMPONENTS[@]} " =~ " waha " ]]; then
        local waha_dash_pass=$(grep "waha_dashboard_password=" "$CREDENTIALS_FILE" | cut -d= -f2)
        echo "WAHA:"
        echo "  URL: https://$WAHA_DOMAIN"
        echo "  Dashboard: admin / $waha_dash_pass"
        echo "  API Key: $(grep "waha_api_key=" "$CREDENTIALS_FILE" | cut -d= -f2)"
        echo
    fi
    
    if [[ " ${INSTALL_COMPONENTS[@]} " =~ " n8n " ]]; then
        local n8n_pass=$(grep "n8n_password=" "$CREDENTIALS_FILE" | cut -d= -f2)
        echo "N8N:"
        echo "  URL: https://$N8N_DOMAIN"
        echo "  Login: admin / $n8n_pass"
        echo
    fi
    
    echo "==================================================================="
    echo
    echo "PRÓXIMOS PASSOS:"
    echo "1. Acesse o WAHA e conecte seu WhatsApp"
    echo "2. Configure webhooks no Chatwoot"
    echo "3. Crie automações no n8n"
    echo
    echo "COMANDOS ÚTEIS:"
    echo "  ./wnc-cli.sh status     - Ver status dos serviços"
    echo "  ./wnc-cli.sh logs       - Ver logs"
    echo "  ./wnc-cli.sh backup     - Fazer backup"
    echo "  ./wnc-cli.sh update     - Atualizar serviços"
    echo
    echo "Logs da instalação em: $LOG_FILE"
    echo "==================================================================="
}

create_management_scripts() {
    info "Criando scripts de gerenciamento..."
    
    # Script de monitoramento
    write_config /usr/local/bin/wnc-monitor <<'EOF'
#!/bin/bash
# Monitor WNC Stack

check_service() {
    local name=$1
    local compose=$2
    echo -n "$name: "
    if docker compose -f "$compose" ps | grep -q "Up"; then
        echo -e "\033[32mOK\033[0m"
    else
        echo -e "\033[31mDOWN\033[0m"
    fi
}

echo "=== WNC Stack Status ==="
check_service "Chatwoot" "/opt/chatwoot/docker-compose.yml"
check_service "WAHA" "/opt/waha/docker-compose.yml"
check_service "n8n" "/opt/n8n/docker-compose.yml"
echo

echo "=== Resource Usage ==="
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
EOF
    
    chmod +x /usr/local/bin/wnc-monitor
    
    success "Scripts de gerenciamento criados"
}

#-----------------------------------------------------------------------------
# Função principal
#-----------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --debug)
                DEBUG_MODE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-dns)
                SKIP_DNS_CHECK=true
                shift
                ;;
            --skip-ssl)
                SKIP_CERT_GENERATION=true
                shift
                ;;
            --chat-domain=*)
                CHAT_DOMAIN="${1#*=}"
                shift
                ;;
            --waha-domain=*)
                WAHA_DOMAIN="${1#*=}"
                shift
                ;;
            --n8n-domain=*)
                N8N_DOMAIN="${1#*=}"
                shift
                ;;
            --email=*)
                EMAIL_SSL="${1#*=}"
                shift
                ;;
            --components=*)
                IFS=',' read -ra INSTALL_COMPONENTS <<< "${1#*=}"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Argumento desconhecido: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
Uso: $0 [OPÇÕES]

OPÇÕES:
    --debug                 Ativa modo debug
    --dry-run              Simula instalação sem fazer alterações
    --skip-dns             Pula verificação de DNS
    --skip-ssl             Pula geração de certificados SSL
    --chat-domain=DOMAIN   Define domínio do Chatwoot
    --waha-domain=DOMAIN   Define domínio do WAHA
    --n8n-domain=DOMAIN    Define domínio do n8n
    --email=EMAIL          Define email para certificados SSL
    --components=LIST      Define componentes para instalar (chatwoot,waha,n8n)
    -h, --help             Mostra esta ajuda

EXEMPLOS:
    # Instalação interativa
    $0
    
    # Instalação automática com todos componentes
    $0 --chat-domain=chat.example.com --waha-domain=waha.example.com --n8n-domain=n8n.example.com --email=admin@example.com
    
    # Instalar apenas Chatwoot
    $0 --components=chatwoot --chat-domain=chat.example.com --email=admin@example.com
    
    # Modo debug com dry-run
    $0 --debug --dry-run

EOF
}

main() {
    # Parse argumentos
    parse_args "$@"
    
    # Se não houver componentes definidos, entra em modo interativo
    if [[ ${#INSTALL_COMPONENTS[@]} -eq 0 ]]; then
        interactive_setup
    fi
    
    # Validações iniciais
    check_prerequisites
    check_ports
    
    # Valida DNS para cada domínio
    if [[ " ${INSTALL_COMPONENTS[@]} " =~ " chatwoot " ]]; then
        validate_dns "$CHAT_DOMAIN" || exit 1
    fi
    if [[ " ${INSTALL_COMPONENTS[@]} " =~ " waha " ]]; then
        validate_dns "$WAHA_DOMAIN" || exit 1
    fi
    if [[ " ${INSTALL_COMPONENTS[@]} " =~ " n8n " ]]; then
        validate_dns "$N8N_DOMAIN" || exit 1
    fi
    
    # Atualiza sistema
    info "Atualizando sistema..."
    apt-get update -qq
    apt-get upgrade -y -qq
    
    # Instala componentes base
    install_docker
    install_nginx
    create_docker_network
    
    # Instala componentes selecionados
    local total_steps=${#INSTALL_COMPONENTS[@]}
    local current_step=0
    
    for component in "${INSTALL_COMPONENTS[@]}"; do
        ((current_step++))
        show_progress $current_step $total_steps "Instalando $component"
        
        case $component in
            chatwoot) install_chatwoot ;;
            waha) install_waha ;;
            n8n) install_n8n ;;
            *) error "Componente desconhecido: $component" ;;
        esac
    done
    
    # Configura Nginx e SSL
    configure_nginx
    install_ssl_certificates
    
    # Cria scripts de gerenciamento
    create_management_scripts
    
    # Testa instalação
    test_installation
    
    # Mostra credenciais e instruções
    show_credentials
}

# Executa função principal
main "$@"
