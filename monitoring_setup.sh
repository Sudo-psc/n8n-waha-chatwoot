#!/usr/bin/env bash
# Instala node_exporter (sistema) + cAdvisor (containers) para Prometheus
set -euo pipefail
log(){ echo -e "\e[96m[MON]\e[0m $*"; }

# node_exporter ---------------------------------------------------------------
log "Instalando node_exporter…"
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
log "Subindo cAdvisor no Docker…"
docker run -d --name=cadvisor --restart=unless-stopped \
  -p 8080:8080 -v /:/rootfs:ro -v /var/run:/var/run:ro \
  -v /sys:/sys:ro -v /var/lib/docker/:/var/lib/docker:ro \
  gcr.io/cadvisor/cadvisor:v0.49.1
log "Monitoring up: node_exporter (9100) e cAdvisor (8080)."
