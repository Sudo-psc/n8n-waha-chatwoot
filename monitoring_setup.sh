#!/usr/bin/env bash
###############################################################################
# Script: monitoring_setup.sh
# Descrição: Configura stack de monitoramento com Prometheus, Grafana,
#            Node Exporter e cAdvisor
# Sistema-alvo: Ubuntu/Debian
# Versão: 2.0.0
# Autor: philipe_cruz@outlook.com
#
# Melhorias v2.0:
# - Validações de sistema e portas
# - Configuração via variáveis de ambiente
# - Sistema de rollback em caso de falha
# - Segurança aprimorada (senhas, SSL)
# - Dashboards pré-configurados
# - Instalação modular
###############################################################################

# Configuração de cores para output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Structured logging
SCRIPT_NAME=$(basename "$0" .sh)
LOG_FILE="/var/log/${SCRIPT_NAME}.log"
CONFIG_DIR="/etc/monitoring"
DATA_DIR="/var/lib/monitoring"
BACKUP_DIR="/var/backups/${SCRIPT_NAME}"

mkdir -p "$(dirname "$LOG_FILE")" "$CONFIG_DIR" "$DATA_DIR" "$BACKUP_DIR"
touch "$LOG_FILE"

log() { 
    local level="$1"
    shift
    echo "$(date '+%F %T') [$level] $*" | tee -a "$LOG_FILE"
}

info()  { echo -e "${GREEN}[INFO]${NC} $*" | tee -a "$LOG_FILE"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"; }
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
            "systemd:*")
                local service="${resource#systemd:}"
                info "Parando e desabilitando serviço: $service"
                systemctl stop "$service" 2>/dev/null || true
                systemctl disable "$service" 2>/dev/null || true
                rm -f "/etc/systemd/system/$service"
                ;;
            "docker:*")
                local container="${resource#docker:}"
                info "Removendo container: $container"
                docker rm -f "$container" 2>/dev/null || true
                ;;
            "compose:*")
                local compose_file="${resource#compose:}"
                info "Removendo stack Docker Compose: $compose_file"
                docker compose -f "$compose_file" down -v 2>/dev/null || true
                ;;
            "user:*")
                local user="${resource#user:}"
                info "Removendo usuário: $user"
                userdel -r "$user" 2>/dev/null || true
                ;;
            "dir:*")
                local dir="${resource#dir:}"
                info "Removendo diretório: $dir"
                rm -rf "$dir"
                ;;
            "file:*")
                local file="${resource#file:}"
                info "Removendo arquivo: $file"
                rm -f "$file"
                ;;
        esac
    done
    
    systemctl daemon-reload 2>/dev/null || true
    info "Rollback concluído"
}

# Configurações padrão (podem ser sobrescritas por variáveis de ambiente)
: "${INSTALL_NODE_EXPORTER:=1}"
: "${INSTALL_CADVISOR:=1}"
: "${INSTALL_PROMETHEUS:=1}"
: "${INSTALL_GRAFANA:=1}"
: "${INSTALL_ALERTMANAGER:=0}"
: "${INSTALL_HTOP:=1}"

# Versões dos componentes
: "${NODE_EXPORTER_VERSION:=1.8.1}"
: "${CADVISOR_VERSION:=v0.49.1}"
: "${PROMETHEUS_VERSION:=v2.52.0}"
: "${GRAFANA_VERSION:=10.4.1}"
: "${ALERTMANAGER_VERSION:=v0.27.0}"

# Portas
: "${NODE_EXPORTER_PORT:=9100}"
: "${CADVISOR_PORT:=8080}"
: "${PROMETHEUS_PORT:=9090}"
: "${GRAFANA_PORT:=3000}"
: "${ALERTMANAGER_PORT:=9093}"

# Configurações de segurança
: "${GRAFANA_ADMIN_USER:=admin}"
: "${GRAFANA_ADMIN_PASSWORD:=}"
: "${ENABLE_SSL:=0}"
: "${SSL_DOMAIN:=}"

# Recursos mínimos
: "${MIN_MEMORY_GB:=2}"
: "${MIN_DISK_GB:=10}"

#-----------------------------------------------------------------------------
# Funções utilitárias
#-----------------------------------------------------------------------------
cmd_exists() { 
    command -v "$1" &>/dev/null 
}

check_port() {
    local port=$1
    local service=$2
    
    if ss -tlnp | grep -q ":${port}"; then
        error "Porta $port já está em uso (necessária para $service)"
        return 1
    fi
    return 0
}

ensure_dir() {
    if [[ ! -d "$1" ]]; then
        mkdir -p "$1"
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
    CREATED_RESOURCES+=("file:$file")
}

generate_password() {
    openssl rand -base64 12 | tr -d "=+/" | cut -c1-16
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
    if ! grep -qi "ubuntu\|debian" /etc/os-release 2>/dev/null; then
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
    
    # Verificar Docker
    if ! cmd_exists docker; then
        error "Docker não está instalado. Execute primeiro: curl -fsSL https://get.docker.com | sh"
        exit 1
    fi
    
    # Verificar portas
    local all_ports_ok=true
    
    [[ "$INSTALL_NODE_EXPORTER" == "1" ]] && ! check_port "$NODE_EXPORTER_PORT" "Node Exporter" && all_ports_ok=false
    [[ "$INSTALL_CADVISOR" == "1" ]] && ! check_port "$CADVISOR_PORT" "cAdvisor" && all_ports_ok=false
    [[ "$INSTALL_PROMETHEUS" == "1" ]] && ! check_port "$PROMETHEUS_PORT" "Prometheus" && all_ports_ok=false
    [[ "$INSTALL_GRAFANA" == "1" ]] && ! check_port "$GRAFANA_PORT" "Grafana" && all_ports_ok=false
    [[ "$INSTALL_ALERTMANAGER" == "1" ]] && ! check_port "$ALERTMANAGER_PORT" "Alertmanager" && all_ports_ok=false
    
    if [[ "$all_ports_ok" != "true" ]]; then
        error "Instalação abortada devido a conflito de portas"
        exit 1
    fi
    
    info "Todos os requisitos do sistema foram atendidos ✓"
}

#-----------------------------------------------------------------------------
# Instalação de dependências base
#-----------------------------------------------------------------------------
install_dependencies() {
    info "Instalando dependências base..."
    
    apt-get update -qq
    apt-get install -y curl wget jq ca-certificates gnupg lsb-release >/dev/null 2>&1
    
    # Docker Compose se não existir
    if ! cmd_exists docker-compose && ! docker compose version &>/dev/null; then
        apt-get install -y docker-compose-plugin >/dev/null 2>&1
    fi
    
    info "Dependências instaladas ✓"
}

#-----------------------------------------------------------------------------
# Instalação do htop
#-----------------------------------------------------------------------------
install_htop() {
    if [[ "$INSTALL_HTOP" != "1" ]]; then
        return
    fi
    
    info "Instalando htop para monitoramento interativo..."
    apt-get install -y htop >/dev/null 2>&1
    info "htop instalado ✓ (use 'htop' para monitoramento em tempo real)"
}

#-----------------------------------------------------------------------------
# Instalação do Node Exporter
#-----------------------------------------------------------------------------
install_node_exporter() {
    if [[ "$INSTALL_NODE_EXPORTER" != "1" ]]; then
        return
    fi
    
    info "Instalando Node Exporter ${NODE_EXPORTER_VERSION}..."
    
    # Criar usuário se não existir
    if ! id -u node_exporter &>/dev/null; then
        useradd --no-create-home --shell /bin/false node_exporter
        CREATED_RESOURCES+=("user:node_exporter")
    fi
    
    # Detectar arquitetura
    local arch=""
    case $(uname -m) in
        x86_64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7l) arch="armv7" ;;
        *) error "Arquitetura não suportada: $(uname -m)"; exit 1 ;;
    esac
    
    # Download e instalação
    local download_url="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}.tar.gz"
    
    info "Baixando Node Exporter..."
    curl -L "$download_url" | tar -xz -C /tmp
    
    # Instalar binário
    cp "/tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}/node_exporter" /usr/local/bin/
    chmod +x /usr/local/bin/node_exporter
    chown node_exporter:node_exporter /usr/local/bin/node_exporter
    
    # Limpar arquivos temporários
    rm -rf "/tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}"
    
    # Criar serviço systemd
    write_config /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Prometheus Node Exporter
Documentation=https://github.com/prometheus/node_exporter
After=network.target

[Service]
Type=simple
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter \\
    --web.listen-address=:${NODE_EXPORTER_PORT} \\
    --collector.filesystem.mount-points-exclude="^/(sys|proc|dev|host|etc|rootfs/var/lib/docker/containers|rootfs/var/lib/docker/overlay2|rootfs/run/docker/netns|rootfs/var/lib/docker/aufs)($$|/)" \\
    --collector.netdev.device-exclude="^(veth.*|br.*|docker.*|virbr.*|lo)$$"

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    CREATED_RESOURCES+=("systemd:node_exporter.service")
    
    # Iniciar serviço
    systemctl daemon-reload
    systemctl enable node_exporter
    systemctl start node_exporter
    
    info "Node Exporter instalado e rodando na porta ${NODE_EXPORTER_PORT} ✓"
}

#-----------------------------------------------------------------------------
# Instalação do cAdvisor
#-----------------------------------------------------------------------------
install_cadvisor() {
    if [[ "$INSTALL_CADVISOR" != "1" ]]; then
        return
    fi
    
    info "Instalando cAdvisor ${CADVISOR_VERSION}..."
    
    # Remover container existente se houver
    docker rm -f cadvisor 2>/dev/null || true
    
    # Executar cAdvisor
    docker run -d \
        --name=cadvisor \
        --restart=unless-stopped \
        --volume=/:/rootfs:ro \
        --volume=/var/run:/var/run:ro \
        --volume=/sys:/sys:ro \
        --volume=/var/lib/docker/:/var/lib/docker:ro \
        --volume=/dev/disk/:/dev/disk:ro \
        --publish=${CADVISOR_PORT}:8080 \
        --detach=true \
        --privileged \
        --device=/dev/kmsg \
        gcr.io/cadvisor/cadvisor:${CADVISOR_VERSION}
    
    CREATED_RESOURCES+=("docker:cadvisor")
    
    info "cAdvisor instalado e rodando na porta ${CADVISOR_PORT} ✓"
}

#-----------------------------------------------------------------------------
# Configuração do Prometheus e Grafana
#-----------------------------------------------------------------------------
setup_monitoring_stack() {
    if [[ "$INSTALL_PROMETHEUS" != "1" ]] && [[ "$INSTALL_GRAFANA" != "1" ]]; then
        return
    fi
    
    info "Configurando stack de monitoramento..."
    
    # Criar diretório
    local stack_dir="/opt/monitoring"
    ensure_dir "$stack_dir"
    ensure_dir "$stack_dir/prometheus"
    ensure_dir "$stack_dir/grafana/dashboards"
    ensure_dir "$stack_dir/grafana/provisioning/dashboards"
    ensure_dir "$stack_dir/grafana/provisioning/datasources"
    ensure_dir "$stack_dir/alertmanager"
    
    # Gerar senha do Grafana se não fornecida
    if [[ -z "$GRAFANA_ADMIN_PASSWORD" ]]; then
        GRAFANA_ADMIN_PASSWORD=$(generate_password)
        info "Senha do Grafana gerada: $GRAFANA_ADMIN_PASSWORD"
        echo "GRAFANA_ADMIN_PASSWORD=$GRAFANA_ADMIN_PASSWORD" >> "$stack_dir/.env"
        chmod 600 "$stack_dir/.env"
    fi
    
    # Configuração do Prometheus
    if [[ "$INSTALL_PROMETHEUS" == "1" ]]; then
        write_config "$stack_dir/prometheus/prometheus.yml" <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitor: 'monitoring-stack'

# Alertmanager configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          ${INSTALL_ALERTMANAGER:+- 'localhost:${ALERTMANAGER_PORT}'}

# Load rules once and periodically evaluate them
rule_files:
  - "rules/*.yml"

# Scrape configurations
scrape_configs:
  # Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:${PROMETHEUS_PORT}']

  # Node Exporter
  ${INSTALL_NODE_EXPORTER:+- job_name: 'node'
    static_configs:
      - targets: ['host.docker.internal:${NODE_EXPORTER_PORT}']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        replacement: 'node-exporter'}

  # cAdvisor
  ${INSTALL_CADVISOR:+- job_name: 'cadvisor'
    static_configs:
      - targets: ['host.docker.internal:${CADVISOR_PORT}']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        replacement: 'cadvisor'}

  # Docker containers via Docker daemon
  - job_name: 'docker'
    static_configs:
      - targets: ['unix:///var/run/docker.sock']
EOF

        # Criar regras de alerta básicas
        ensure_dir "$stack_dir/prometheus/rules"
        write_config "$stack_dir/prometheus/rules/basic.yml" <<'EOF'
groups:
  - name: basic
    interval: 30s
    rules:
      # Alta utilização de CPU
      - alert: HighCpuUsage
        expr: 100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Alta utilização de CPU (instance {{ $labels.instance }})"
          description: "CPU está acima de 80% por mais de 5 minutos\n  VALUE = {{ $value }}\n  LABELS = {{ $labels }}"

      # Alta utilização de memória
      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Alta utilização de memória (instance {{ $labels.instance }})"
          description: "Memória está acima de 85% por mais de 5 minutos\n  VALUE = {{ $value }}\n  LABELS = {{ $labels }}"

      # Disco cheio
      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 15
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Espaço em disco baixo (instance {{ $labels.instance }})"
          description: "Menos de 15% de espaço livre no disco\n  VALUE = {{ $value }}\n  LABELS = {{ $labels }}"
EOF
    fi
    
    # Configuração do Grafana
    if [[ "$INSTALL_GRAFANA" == "1" ]]; then
        # Datasource do Prometheus
        write_config "$stack_dir/grafana/provisioning/datasources/prometheus.yml" <<EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
EOF

        # Dashboard provisioning
        write_config "$stack_dir/grafana/provisioning/dashboards/default.yml" <<EOF
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    options:
      path: /var/lib/grafana/dashboards
EOF

        # Dashboard básico do Node Exporter
        if [[ "$INSTALL_NODE_EXPORTER" == "1" ]]; then
            info "Baixando dashboard do Node Exporter..."
            curl -sL https://grafana.com/api/dashboards/1860/revisions/latest/download \
                -o "$stack_dir/grafana/dashboards/node-exporter.json" 2>/dev/null || \
                warn "Não foi possível baixar dashboard do Node Exporter"
        fi
        
        # Dashboard do Docker/cAdvisor
        if [[ "$INSTALL_CADVISOR" == "1" ]]; then
            info "Baixando dashboard do Docker..."
            curl -sL https://grafana.com/api/dashboards/893/revisions/latest/download \
                -o "$stack_dir/grafana/dashboards/docker.json" 2>/dev/null || \
                warn "Não foi possível baixar dashboard do Docker"
        fi
    fi
    
    # Docker Compose
    write_config "$stack_dir/docker-compose.yml" <<EOF
version: '3.8'

services:
EOF

    # Adicionar Prometheus se habilitado
    if [[ "$INSTALL_PROMETHEUS" == "1" ]]; then
        cat >> "$stack_dir/docker-compose.yml" <<EOF
  prometheus:
    image: prom/prometheus:${PROMETHEUS_VERSION}
    container_name: prometheus
    restart: unless-stopped
    user: "0:0"
    ports:
      - "${PROMETHEUS_PORT}:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./prometheus/rules:/etc/prometheus/rules:ro
      - prometheus-data:/prometheus
      - /var/run/docker.sock:/var/run/docker.sock:ro
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
      - '--web.enable-lifecycle'
      - '--storage.tsdb.retention.time=30d'
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - monitoring

EOF
    fi
    
    # Adicionar Grafana se habilitado
    if [[ "$INSTALL_GRAFANA" == "1" ]]; then
        cat >> "$stack_dir/docker-compose.yml" <<EOF
  grafana:
    image: grafana/grafana:${GRAFANA_VERSION}
    container_name: grafana
    restart: unless-stopped
    user: "0:0"
    ports:
      - "${GRAFANA_PORT}:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource
      - GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/var/lib/grafana/dashboards/node-exporter.json
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/var/lib/grafana/dashboards:ro
    networks:
      - monitoring
    ${INSTALL_PROMETHEUS:+depends_on:
      - prometheus}

EOF
    fi
    
    # Adicionar Alertmanager se habilitado
    if [[ "$INSTALL_ALERTMANAGER" == "1" ]]; then
        # Configuração do Alertmanager
        write_config "$stack_dir/alertmanager/alertmanager.yml" <<EOF
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'null'
  routes:
    - match:
        severity: critical
      receiver: 'critical'
      continue: true

receivers:
  - name: 'null'
  
  - name: 'critical'
    # Configurar webhook, email, etc. conforme necessário

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'dev', 'instance']
EOF
        
        cat >> "$stack_dir/docker-compose.yml" <<EOF
  alertmanager:
    image: prom/alertmanager:${ALERTMANAGER_VERSION}
    container_name: alertmanager
    restart: unless-stopped
    ports:
      - "${ALERTMANAGER_PORT}:9093"
    volumes:
      - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
      - alertmanager-data:/alertmanager
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--storage.path=/alertmanager'
    networks:
      - monitoring

EOF
    fi
    
    # Finalizar docker-compose.yml
    cat >> "$stack_dir/docker-compose.yml" <<EOF
networks:
  monitoring:
    driver: bridge

volumes:
  ${INSTALL_PROMETHEUS:+prometheus-data:}
  ${INSTALL_GRAFANA:+grafana-data:}
  ${INSTALL_ALERTMANAGER:+alertmanager-data:}
EOF
    
    CREATED_RESOURCES+=("compose:$stack_dir/docker-compose.yml")
    
    # Iniciar stack
    info "Iniciando stack de monitoramento..."
    cd "$stack_dir"
    docker compose up -d
    
    # Aguardar serviços ficarem prontos
    sleep 10
    
    info "Stack de monitoramento configurado ✓"
}

#-----------------------------------------------------------------------------
# Configuração de Nginx reverso (opcional)
#-----------------------------------------------------------------------------
setup_nginx_proxy() {
    if [[ "$ENABLE_SSL" != "1" ]] || [[ -z "$SSL_DOMAIN" ]]; then
        return
    fi
    
    if ! cmd_exists nginx; then
        info "Instalando Nginx..."
        apt-get install -y nginx certbot python3-certbot-nginx >/dev/null 2>&1
    fi
    
    info "Configurando proxy reverso com SSL..."
    
    # Configurações do Nginx para cada serviço
    local services=()
    [[ "$INSTALL_PROMETHEUS" == "1" ]] && services+=("prometheus:$PROMETHEUS_PORT")
    [[ "$INSTALL_GRAFANA" == "1" ]] && services+=("grafana:$GRAFANA_PORT")
    [[ "$INSTALL_ALERTMANAGER" == "1" ]] && services+=("alertmanager:$ALERTMANAGER_PORT")
    
    for service_port in "${services[@]}"; do
        local service="${service_port%%:*}"
        local port="${service_port##*:}"
        local subdomain="${service}.${SSL_DOMAIN}"
        
        write_config "/etc/nginx/sites-available/$subdomain" <<EOF
server {
    listen 80;
    server_name $subdomain;
    
    location / {
        proxy_pass http://localhost:$port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support for Grafana
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
        
        ln -sf "/etc/nginx/sites-available/$subdomain" "/etc/nginx/sites-enabled/"
        
        # Obter certificado SSL
        certbot --nginx -d "$subdomain" --non-interactive --agree-tos \
            --email "${SSL_EMAIL:-admin@$SSL_DOMAIN}" --redirect
    done
    
    nginx -t && systemctl reload nginx
    info "Proxy reverso com SSL configurado ✓"
}

#-----------------------------------------------------------------------------
# Verificação de saúde
#-----------------------------------------------------------------------------
health_check() {
    info "Verificando saúde dos serviços..."
    echo
    
    local all_healthy=true
    
    # Node Exporter
    if [[ "$INSTALL_NODE_EXPORTER" == "1" ]]; then
        if systemctl is-active --quiet node_exporter; then
            echo -e "${GREEN}✓${NC} Node Exporter: http://localhost:${NODE_EXPORTER_PORT}/metrics"
        else
            echo -e "${RED}✗${NC} Node Exporter: não está rodando"
            all_healthy=false
        fi
    fi
    
    # cAdvisor
    if [[ "$INSTALL_CADVISOR" == "1" ]]; then
        if docker ps | grep -q cadvisor; then
            echo -e "${GREEN}✓${NC} cAdvisor: http://localhost:${CADVISOR_PORT}"
        else
            echo -e "${RED}✗${NC} cAdvisor: não está rodando"
            all_healthy=false
        fi
    fi
    
    # Prometheus
    if [[ "$INSTALL_PROMETHEUS" == "1" ]]; then
        if curl -s "http://localhost:${PROMETHEUS_PORT}/-/healthy" >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Prometheus: http://localhost:${PROMETHEUS_PORT}"
        else
            echo -e "${RED}✗${NC} Prometheus: não está respondendo"
            all_healthy=false
        fi
    fi
    
    # Grafana
    if [[ "$INSTALL_GRAFANA" == "1" ]]; then
        if curl -s "http://localhost:${GRAFANA_PORT}/api/health" >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Grafana: http://localhost:${GRAFANA_PORT}"
        else
            echo -e "${RED}✗${NC} Grafana: não está respondendo"
            all_healthy=false
        fi
    fi
    
    # Alertmanager
    if [[ "$INSTALL_ALERTMANAGER" == "1" ]]; then
        if curl -s "http://localhost:${ALERTMANAGER_PORT}/-/healthy" >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Alertmanager: http://localhost:${ALERTMANAGER_PORT}"
        else
            echo -e "${RED}✗${NC} Alertmanager: não está respondendo"
            all_healthy=false
        fi
    fi
    
    echo
    return $([[ "$all_healthy" == "true" ]] && echo 0 || echo 1)
}

#-----------------------------------------------------------------------------
# Criar scripts auxiliares
#-----------------------------------------------------------------------------
create_helper_scripts() {
    info "Criando scripts auxiliares..."
    
    # Script de status
    write_config /usr/local/bin/monitoring-status <<'EOF'
#!/bin/bash
echo "=== Status do Monitoramento ==="
echo
echo "Serviços systemd:"
systemctl status node_exporter --no-pager 2>/dev/null | head -n 3 || echo "Node Exporter: não instalado"
echo
echo "Containers Docker:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(prometheus|grafana|cadvisor|alertmanager)" || echo "Nenhum container de monitoramento rodando"
echo
echo "Uso de recursos:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" $(docker ps -q --filter name=prometheus --filter name=grafana --filter name=cadvisor --filter name=alertmanager) 2>/dev/null || true
EOF
    
    chmod +x /usr/local/bin/monitoring-status
    
    # Script de backup das configurações
    write_config /usr/local/bin/monitoring-backup <<EOF
#!/bin/bash
BACKUP_DIR="/var/backups/monitoring/\$(date +%Y%m%d_%H%M%S)"
mkdir -p "\$BACKUP_DIR"

echo "Fazendo backup das configurações de monitoramento..."

# Backup das configurações
cp -r /opt/monitoring "\$BACKUP_DIR/" 2>/dev/null || true
cp -r $CONFIG_DIR "\$BACKUP_DIR/" 2>/dev/null || true

# Backup dos volumes Docker
docker run --rm -v prometheus-data:/data -v "\$BACKUP_DIR":/backup alpine tar czf /backup/prometheus-data.tar.gz -C /data . 2>/dev/null || true
docker run --rm -v grafana-data:/data -v "\$BACKUP_DIR":/backup alpine tar czf /backup/grafana-data.tar.gz -C /data . 2>/dev/null || true

echo "Backup salvo em: \$BACKUP_DIR"
EOF
    
    chmod +x /usr/local/bin/monitoring-backup
    
    info "Scripts auxiliares criados ✓"
}

#-----------------------------------------------------------------------------
# Mostrar resumo final
#-----------------------------------------------------------------------------
show_summary() {
    echo
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      Stack de Monitoramento Instalado com Sucesso! 🎉     ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    echo -e "${BLUE}Componentes instalados:${NC}"
    [[ "$INSTALL_HTOP" == "1" ]] && echo " • htop (monitoramento interativo)"
    [[ "$INSTALL_NODE_EXPORTER" == "1" ]] && echo " • Node Exporter ${NODE_EXPORTER_VERSION} (porta ${NODE_EXPORTER_PORT})"
    [[ "$INSTALL_CADVISOR" == "1" ]] && echo " • cAdvisor ${CADVISOR_VERSION} (porta ${CADVISOR_PORT})"
    [[ "$INSTALL_PROMETHEUS" == "1" ]] && echo " • Prometheus ${PROMETHEUS_VERSION} (porta ${PROMETHEUS_PORT})"
    [[ "$INSTALL_GRAFANA" == "1" ]] && echo " • Grafana ${GRAFANA_VERSION} (porta ${GRAFANA_PORT})"
    [[ "$INSTALL_ALERTMANAGER" == "1" ]] && echo " • Alertmanager ${ALERTMANAGER_VERSION} (porta ${ALERTMANAGER_PORT})"
    
    echo
    echo -e "${BLUE}URLs de acesso:${NC}"
    [[ "$INSTALL_PROMETHEUS" == "1" ]] && echo " • Prometheus: http://localhost:${PROMETHEUS_PORT}"
    [[ "$INSTALL_GRAFANA" == "1" ]] && echo " • Grafana: http://localhost:${GRAFANA_PORT}"
    [[ "$INSTALL_ALERTMANAGER" == "1" ]] && echo " • Alertmanager: http://localhost:${ALERTMANAGER_PORT}"
    [[ "$INSTALL_CADVISOR" == "1" ]] && echo " • cAdvisor: http://localhost:${CADVISOR_PORT}"
    
    if [[ "$INSTALL_GRAFANA" == "1" ]]; then
        echo
        echo -e "${YELLOW}Credenciais do Grafana:${NC}"
        echo " • Usuário: ${GRAFANA_ADMIN_USER}"
        echo " • Senha: ${GRAFANA_ADMIN_PASSWORD}"
        [[ -f "/opt/monitoring/.env" ]] && echo " • Salvas em: /opt/monitoring/.env"
    fi
    
    echo
    echo -e "${BLUE}Comandos úteis:${NC}"
    echo " • monitoring-status  - Ver status dos serviços"
    echo " • monitoring-backup  - Fazer backup das configurações"
    [[ "$INSTALL_HTOP" == "1" ]] && echo " • htop              - Monitoramento interativo do sistema"
    echo " • docker stats      - Estatísticas dos containers"
    
    echo
    echo -e "${YELLOW}Próximos passos:${NC}"
    echo " 1. Acesse o Grafana e explore os dashboards"
    echo " 2. Configure alertas no Prometheus/Alertmanager"
    echo " 3. Adicione mais exporters conforme necessário"
    echo " 4. Customize os dashboards do Grafana"
    
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
    echo "║         Stack de Monitoramento - Installer v2.0           ║"
    echo "║    Prometheus + Grafana + Node Exporter + cAdvisor        ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Verificações iniciais
    check_system_requirements
    
    # Instalação
    install_dependencies
    install_htop
    install_node_exporter
    install_cadvisor
    setup_monitoring_stack
    setup_nginx_proxy
    create_helper_scripts
    
    # Verificação final
    if health_check; then
        show_summary
        info "Instalação concluída com sucesso!"
    else
        error "Alguns serviços não estão funcionando corretamente"
        error "Verifique os logs para mais detalhes"
        exit 1
    fi
}

# Executar função principal
main "$@"
