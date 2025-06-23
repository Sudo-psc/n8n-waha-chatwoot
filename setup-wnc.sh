
#!/usr/bin/env bash
###############################################################################
#  Auto-installer: Chatwoot + WAHA + n8n (Docker) com Nginx e HTTPS
#  Domínios fixos:
#    chat.saraivavision.com.br  → Chatwoot
#    waha.saraivavision.com.br  → WAHA
#    n8n.saraivavision.com.br   → n8n
#  Autor de contato: philipe_cruz@outlook.com
###############################################################################

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

CHAT_DOMAIN="chat.saraivavision.com.br"
WAHA_DOMAIN="waha.saraivavision.com.br"
N8N_DOMAIN="n8n.saraivavision.com.br"
EMAIL_SSL="philipe_cruz@outlook.com"
STACK_NET="wcn_net"

#-----------------------------------------------------------------------------
# Funções utilitárias
#-----------------------------------------------------------------------------
apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" >/dev/null
}
cmd_exists() { command -v "$1" &>/dev/null; }

# cria diretório se não existir
ensure_dir() {
  if [[ -d $1 ]]; then
    info "Diretório $1 já existe — pulando"
  else
    mkdir -p "$1"
    chmod 755 "$1"
  fi
}

# faz backup de arquivo existente e grava conteúdo
write_config() {
  local file=$1
  shift
  if [[ -f $file ]]; then
    local bk
    bk="${file}.bak.$(date +%s)"
    warn "$file existe, backup em $bk"
    cp "$file" "$bk"
  fi
  cat > "$file" "$@"
}

#-----------------------------------------------------------------------------
# 0) Pré-requisitos
#-----------------------------------------------------------------------------
[[ $EUID -eq 0 ]] || { error "Rode como root (sudo)"; exit 1; }
grep -qi ubuntu /etc/os-release || warn "Sistema não Ubuntu — tente por sua conta e risco"
info "Atualizando índice APT..."
apt-get update -qq

#-----------------------------------------------------------------------------
# 1) Docker & docker-compose-plugin
#-----------------------------------------------------------------------------
if ! cmd_exists docker; then
  info "Instalando Docker Engine..."
  curl -fsSL https://get.docker.com | sh >/dev/null
else
  info "Docker já instalado — pulando"
fi
apt_install docker-compose-plugin
systemctl enable --now docker

#-----------------------------------------------------------------------------
# 2) Nginx + Certbot
#-----------------------------------------------------------------------------
apt_install nginx certbot python3-certbot-nginx

#-----------------------------------------------------------------------------
# 3) Rede Docker
#-----------------------------------------------------------------------------
if ! docker network inspect $STACK_NET &>/dev/null; then
  info "Criando rede Docker $STACK_NET"
  docker network create "$STACK_NET"
fi

#-----------------------------------------------------------------------------
# 4) Estrutura de diretórios
#-----------------------------------------------------------------------------
for dir in /opt/chatwoot /opt/waha /opt/n8n; do
  ensure_dir "$dir"
done

###############################################################################
# 4A) Chatwoot
###############################################################################
info "Configurando Chatwoot..."
write_config /opt/chatwoot/.env <<EOF
NODE_ENV=production
RAILS_ENV=production
INSTALLATION_ENV=docker
SECRET_KEY_BASE=$(openssl rand -hex 64)
FRONTEND_URL=https://${CHAT_DOMAIN}
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_USER=chatwoot
POSTGRES_USERNAME=chatwoot
POSTGRES_PASSWORD=chatwoot
POSTGRES_DB=chatwoot
REDIS_URL=redis://redis:6379/0
EOF

write_config /opt/chatwoot/redis.conf <<'RED'
appendonly yes
save 900 1
save 300 10
save 60 10000
RED

write_config /opt/chatwoot/docker-compose.yml <<EOF
version: "3.8"
services:
  rails:
    image: chatwoot/chatwoot:latest
    env_file: .env
    depends_on: [postgres, redis]
    entrypoint: docker/entrypoints/rails.sh
    command: ["bundle", "exec", "rails", "s", "-p", "3000", "-b", "0.0.0.0"]
    networks: [$STACK_NET]
    ports: ["3000:3000"]
    restart: always
  sidekiq:
    image: chatwoot/chatwoot:latest
    env_file: .env
    depends_on: [postgres, redis]
    entrypoint: docker/entrypoints/rails.sh
    command: ["bundle", "exec", "sidekiq", "-C", "config/sidekiq.yml"]
    networks: [$STACK_NET]
    restart: always
  postgres:
    image: pgvector/pgvector:pg13
    environment:
      POSTGRES_USER: chatwoot
      POSTGRES_PASSWORD: chatwoot
      POSTGRES_DB: chatwoot
    volumes: [pg_data:/var/lib/postgresql/data]
    networks: [$STACK_NET]
    restart: always
  redis:
    image: redis:7
    command: ["redis-server","/usr/local/etc/redis/redis.conf"]
    volumes:
      - ./redis.conf:/usr/local/etc/redis/redis.conf:ro
      - redis_data:/data
    networks: [$STACK_NET]
    restart: always
networks:
  $STACK_NET: {external: true}
volumes:
  pg_data: {}
  redis_data: {}
EOF

docker compose -f /opt/chatwoot/docker-compose.yml up -d
# Aguarda o Postgres responder antes de preparar o banco
info "Aguardando Postgres..."
until docker compose -f /opt/chatwoot/docker-compose.yml exec -T postgres \
  pg_isready -h postgres -p 5432 -U chatwoot >/dev/null; do
  sleep 2
done
docker compose -f /opt/chatwoot/docker-compose.yml run --rm rails bundle exec rails db:chatwoot_prepare

###############################################################################
# 4B) WAHA
###############################################################################
info "Configurando WAHA..."
write_config /opt/waha/.env <<EOF
WHATSAPP_API_KEY=$(openssl rand -hex 32)
WAHA_BASE_URL=https://${WAHA_DOMAIN}
WAHA_DASHBOARD_USERNAME=admin
WAHA_DASHBOARD_PASSWORD=$(openssl rand -hex 12)
WHATSAPP_SWAGGER_USERNAME=api
WHATSAPP_SWAGGER_PASSWORD=$(openssl rand -hex 12)
EOF

write_config /opt/waha/docker-compose.yml <<EOF
version: "3.8"
services:
  waha:
    image: devlikeapro/whatsapp-http-api:latest
    env_file: .env
    volumes: [sessions:/app/.sessions]
    ports: ["3001:3000"]
    networks: [$STACK_NET]
    restart: always
networks:
  $STACK_NET: {external: true}
volumes:
  sessions: {}
EOF

docker compose -f /opt/waha/docker-compose.yml up -d

###############################################################################
# 4C) n8n
###############################################################################
info "Configurando n8n..."
write_config /opt/n8n/.env <<EOF
N8N_HOST=${N8N_DOMAIN}
N8N_PORT=5678
N8N_PROTOCOL=https
N8N_SECURE_COOKIE=false
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=$(openssl rand -hex 12)
EOF

write_config /opt/n8n/docker-compose.yml <<EOF
version: "3.8"
services:
  n8n:
    image: n8nio/n8n:latest
    env_file: .env
    volumes: [n8n_data:/home/node/.n8n]
    ports: ["3002:5678"]
    networks: [$STACK_NET]
    restart: always
networks:
  $STACK_NET: {external: true}
volumes:
  n8n_data: {}
EOF

docker compose -f /opt/n8n/docker-compose.yml up -d

#-----------------------------------------------------------------------------
# 5) Nginx server blocks
#-----------------------------------------------------------------------------
create_vhost() {
  local domain=$1 port=$2

  write_config "/etc/nginx/sites-available/${domain}" <<CONF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};
    
    # Redirecionar todo tráfego HTTP para HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${domain};

    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Content-Security-Policy "default-src 'self' 'unsafe-inline' 'unsafe-eval'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:;" always;
    underscores_in_headers on;

    set \$upstream 127.0.0.1:${port};
    location / {
        proxy_pass http://\$upstream;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_buffering off;
        client_max_body_size 0;
        proxy_read_timeout 36000s;
    }
}
CONF

  ln -sf "/etc/nginx/sites-available/${domain}" "/etc/nginx/sites-enabled/${domain}"
}

# Criar configurações básicas primeiro para obter certificados
create_basic_vhost() {
  local domain=$1 port=$2
  write_config "/etc/nginx/sites-available/${domain}" <<CONF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};
    
    location / {
        proxy_pass http://127.0.0.1:${port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
CONF
  ln -sf "/etc/nginx/sites-available/${domain}" "/etc/nginx/sites-enabled/${domain}"
}

info "Criando configurações básicas do Nginx..."
create_basic_vhost "$CHAT_DOMAIN" 3000
create_basic_vhost "$WAHA_DOMAIN" 3001
create_basic_vhost "$N8N_DOMAIN" 3002
nginx -t && systemctl reload nginx

#-----------------------------------------------------------------------------
# 6) Certificados Let's Encrypt
#-----------------------------------------------------------------------------
info "Emitindo certificados SSL..."
for d in "$CHAT_DOMAIN" "$WAHA_DOMAIN" "$N8N_DOMAIN"; do
  certbot --nginx --non-interactive --agree-tos \
    --no-eff-email -m "$EMAIL_SSL" -d "$d" --redirect --hsts \
    --deploy-hook "systemctl reload nginx"
done

#-----------------------------------------------------------------------------
# 6B) Configurações finais do Nginx com CSP corrigida
#-----------------------------------------------------------------------------
info "Atualizando configurações do Nginx com segurança aprimorada..."
create_vhost "$CHAT_DOMAIN" 3000
create_vhost "$WAHA_DOMAIN" 3001
create_vhost "$N8N_DOMAIN" 3002
nginx -t && systemctl reload nginx

# agenda renovação automática
RENEW_CRON="/etc/cron.d/certbot_renew"
if [[ ! -f $RENEW_CRON ]]; then
  echo "0 2 * * * root certbot renew --quiet --deploy-hook 'systemctl reload nginx'" \
    > "$RENEW_CRON"
  chmod 644 "$RENEW_CRON"
  info "Cron diário de renovação criado em $RENEW_CRON"
fi

#-----------------------------------------------------------------------------
# 7) Scripts de teste e utilitários
#-----------------------------------------------------------------------------
info "Criando scripts de teste..."

# Script de teste do WAHA
write_config "/root/test-waha-dashboard.sh" <<'WAHA_TEST'
#!/bin/bash

# Script para testar o dashboard do WAHA
# Criado para verificar se todas as funcionalidades estão funcionando

echo "🔍 Testando Dashboard do WAHA..."
echo "================================"

# Teste 1: Página principal do dashboard
echo "1️⃣ Testando página principal do dashboard..."
response=$(curl -s -o /dev/null -w "%{http_code}" https://waha.saraivavision.com.br/dashboard/)
if [ "$response" = "200" ]; then
    echo "✅ Dashboard principal: OK (HTTP $response)"
else
    echo "❌ Dashboard principal: ERRO (HTTP $response)"
fi

# Teste 2: Recursos CSS
echo "2️⃣ Testando recursos CSS..."
css_response=$(curl -s -o /dev/null -w "%{http_code}" https://waha.saraivavision.com.br/dashboard/_nuxt/entry.*.css)
if [ "$css_response" = "200" ]; then
    echo "✅ CSS: OK (HTTP $css_response)"
else
    echo "❌ CSS: ERRO (HTTP $css_response)"
fi

# Teste 3: API do WAHA
echo "3️⃣ Testando API do WAHA..."
api_response=$(curl -s -o /dev/null -w "%{http_code}" https://waha.saraivavision.com.br/api/sessions)
if [ "$api_response" = "200" ]; then
    echo "✅ API: OK (HTTP $api_response)"
else
    echo "❌ API: ERRO (HTTP $api_response)"
fi

echo ""
echo "🎯 Teste completo finalizado!"
echo "🌐 https://waha.saraivavision.com.br/dashboard/"
WAHA_TEST

# Script de teste do Chatwoot
write_config "/root/test-chatwoot.sh" <<'CHAT_TEST'
#!/bin/bash

# Script para testar o Chatwoot
# Criado para verificar se todas as funcionalidades estão funcionando

echo "🔍 Testando Chatwoot..."
echo "====================="

# Teste 1: Página principal
echo "1️⃣ Testando página principal..."
response=$(curl -s -o /dev/null -w "%{http_code}" https://chat.saraivavision.com.br/)
if [ "$response" = "200" ]; then
    echo "✅ Página principal: OK (HTTP $response)"
else
    echo "❌ Página principal: ERRO (HTTP $response)"
fi

# Teste 2: API do Chatwoot
echo "2️⃣ Testando API do Chatwoot..."
api_response=$(curl -s -o /dev/null -w "%{http_code}" https://chat.saraivavision.com.br/api/v1/profile)
if [ "$api_response" = "401" ] || [ "$api_response" = "200" ]; then
    echo "✅ API: OK (HTTP $api_response - esperado 401 sem autenticação)"
else
    echo "❌ API: ERRO (HTTP $api_response)"
fi

# Teste 3: Redirecionamento HTTP para HTTPS
echo "3️⃣ Testando redirecionamento HTTP → HTTPS..."
redirect_response=$(curl -s -o /dev/null -w "%{http_code}" http://chat.saraivavision.com.br/)
if [ "$redirect_response" = "301" ]; then
    echo "✅ Redirecionamento: OK (HTTP $redirect_response)"
else
    echo "❌ Redirecionamento: ERRO (HTTP $redirect_response)"
fi

echo ""
echo "🎯 Teste completo finalizado!"
echo "🌐 https://chat.saraivavision.com.br/"
CHAT_TEST

# Script de verificação geral
write_config "/root/check-services.sh" <<'CHECK_SERVICES'
#!/bin/bash

# Verificação geral dos serviços
echo "🔍 Verificando todos os serviços..."
echo "=================================="

echo "📋 Status dos containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "🌐 Testando URLs:"

# Teste Chatwoot
chat_status=$(curl -s -o /dev/null -w "%{http_code}" https://chat.saraivavision.com.br)
if [ "$chat_status" = "200" ]; then
    echo "✅ Chatwoot: https://chat.saraivavision.com.br (HTTP $chat_status)"
else
    echo "❌ Chatwoot: https://chat.saraivavision.com.br (HTTP $chat_status)"
fi

# Teste WAHA
waha_status=$(curl -s -o /dev/null -w "%{http_code}" https://waha.saraivavision.com.br)
if [ "$waha_status" = "200" ]; then
    echo "✅ WAHA: https://waha.saraivavision.com.br (HTTP $waha_status)"
else
    echo "❌ WAHA: https://waha.saraivavision.com.br (HTTP $waha_status)"
fi

# Teste n8n
n8n_status=$(curl -s -o /dev/null -w "%{http_code}" https://n8n.saraivavision.com.br)
if [ "$n8n_status" = "200" ] || [ "$n8n_status" = "401" ]; then
    echo "✅ n8n: https://n8n.saraivavision.com.br (HTTP $n8n_status)"
else
    echo "❌ n8n: https://n8n.saraivavision.com.br (HTTP $n8n_status)"
fi

echo ""
echo "🎯 Verificação concluída!"
CHECK_SERVICES

chmod +x /root/test-waha-dashboard.sh /root/test-chatwoot.sh /root/check-services.sh
info "Scripts de teste criados em /root/"

#-----------------------------------------------------------------------------
# 8) Conclusão
#-----------------------------------------------------------------------------
echo -e "\n\033[1;32m🎉 Instalação concluída com sucesso!\033[0m"
echo "📋 URLs de acesso:"
echo " • Chatwoot:  https://${CHAT_DOMAIN}"
echo " • WAHA:      https://${WAHA_DOMAIN}"
echo " • n8n:       https://${N8N_DOMAIN}"
echo ""
echo "🔧 Scripts úteis criados:"
echo " • /root/check-services.sh       - Verificação geral dos serviços"
echo " • /root/test-chatwoot.sh        - Teste completo do Chatwoot"
echo " • /root/test-waha-dashboard.sh  - Teste completo do WAHA"
echo ""
echo "📖 Configurações aplicadas:"
echo " • ✅ CSP otimizada para aplicações JavaScript modernas"
echo " • ✅ Redirecionamento HTTP → HTTPS automático"
echo " • ✅ Cabeçalhos de segurança configurados"
echo " • ✅ Renovação automática de certificados SSL"
echo ""
echo "🚀 Próximos passos:"
echo "1. Execute: /root/check-services.sh para verificar se tudo está funcionando"
echo "2. Acesse o WAHA e leia o QR code do WhatsApp"
echo "3. Configure suas automatizações no n8n"
echo "4. Configure sua conta no Chatwoot"
