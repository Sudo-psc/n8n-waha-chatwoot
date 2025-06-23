#!/usr/bin/env bash
# Instala node_exporter (sistema) + cAdvisor (containers) para Prometheus

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

# Ferramenta simples ---------------------------------------------------------
info "Instalando htop para monitoramento rápido…"
apt-get update -y >/dev/null
apt-get install -y htop >/dev/null
info "Use 'htop' ou 'docker stats' para ver o consumo em tempo real."

# node_exporter ---------------------------------------------------------------
info "Instalando node_exporter…"
useradd -rs /bin/false node_exporter 2>/dev/null || true
VER="1.8.1"
curl -L https://github.com/prometheus/node_exporter/releases/download/v${VER}/node_exporter-${VER}.linux-amd64.tar.gz \
 | tar -xz -C /usr/local/bin --strip-components=1 node_exporter-${VER}.linux-amd64/node_exporter
cat >/etc/systemd/system/node_exporter.service <<'EOF'
[Unit]
Description=Prometheus Node Exporter
After=network.target
[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter
[Install]
WantedBy=default.target
EOF
systemctl enable --now node_exporter

# cAdvisor --------------------------------------------------------------------
info "Subindo cAdvisor no Docker…"
docker run -d --name=cadvisor --restart=unless-stopped \
  -p 8080:8080 -v /:/rootfs:ro -v /var/run:/var/run:ro \
  -v /sys:/sys:ro -v /var/lib/docker/:/var/lib/docker:ro \
  gcr.io/cadvisor/cadvisor:v0.49.1

# Prometheus + Grafana --------------------------------------------------------
info "Configurando Prometheus e Grafana via Docker Compose…"
mkdir -p /opt/monitoring
cat >/opt/monitoring/docker-compose.yml <<'EOF'
version: '3'
services:
  prometheus:
    image: prom/prometheus:v2.52.0
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
  grafana:
    image: grafana/grafana:10.3.1
    ports:
      - "3000:3000"
    volumes:
      - grafana-data:/var/lib/grafana
volumes:
  prometheus-data:
  grafana-data:
EOF
cat >/opt/monitoring/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['localhost:8080']
EOF
docker compose -f /opt/monitoring/docker-compose.yml up -d

info "Monitoring up: node_exporter (9100), cAdvisor (8080), Prometheus (9090) e Grafana (3000)."
