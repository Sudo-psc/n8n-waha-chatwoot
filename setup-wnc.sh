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

###############################################################################
# Configuração - pode ser sobrescrita via opções ou variáveis de ambiente
###############################################################################
# Valores padrão
CHAT_DOMAIN_DEFAULT="chat.saraivavision.com.br"
WAHA_DOMAIN_DEFAULT="waha.saraivavision.com.br"
N8N_DOMAIN_DEFAULT="n8n.saraivavision.com.br"
EMAIL_SSL_DEFAULT="philipe_cruz@outlook.com"

# Permite definir valores pelas variáveis ou opções
CHAT_DOMAIN="${CHAT_DOMAIN:-$CHAT_DOMAIN_DEFAULT}"
WAHA_DOMAIN="${WAHA_DOMAIN:-$WAHA_DOMAIN_DEFAULT}"
N8N_DOMAIN="${N8N_DOMAIN:-$N8N_DOMAIN_DEFAULT}"
EMAIL_SSL="${EMAIL_SSL:-$EMAIL_SSL_DEFAULT}"

usage() {
  cat <<USAGE
Uso: $0 [opções]
  -c DOM  Domínio do Chatwoot (padrão: $CHAT_DOMAIN_DEFAULT)
  -w DOM  Domínio do WAHA (padrão: $WAHA_DOMAIN_DEFAULT)
  -n DOM  Domínio do n8n (padrão: $N8N_DOMAIN_DEFAULT)
  -e MAIL E-mail para SSL (padrão: $EMAIL_SSL_DEFAULT)
  -h      Mostra esta ajuda e sai
Também é possível definir CHAT_DOMAIN, WAHA_DOMAIN, N8N_DOMAIN e EMAIL_SSL
como variáveis de ambiente.
USAGE
  exit 0
}

while getopts "c:w:n:e:h" opt; do
  case $opt in
    c) CHAT_DOMAIN=$OPTARG ;;
    w) WAHA_DOMAIN=$OPTARG ;;
    n) N8N_DOMAIN=$OPTARG ;;
    e) EMAIL_SSL=$OPTARG ;;
    h) usage ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
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
  server_name ${domain};
  set \$upstream 127.0.0.1:${port};
  add_header X-Frame-Options "SAMEORIGIN" always;
  add_header X-Content-Type-Options "nosniff" always;
  add_header Content-Security-Policy "default-src 'self';" always;
  underscores_in_headers on;
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
  listen 80;
}
CONF

  ln -sf "/etc/nginx/sites-available/${domain}" "/etc/nginx/sites-enabled/${domain}"
}

info "Criando virtual hosts Nginx..."
create_vhost "$CHAT_DOMAIN" 3000
create_vhost "$WAHA_DOMAIN" 3001
create_vhost "$N8N_DOMAIN" 3002
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

# agenda renovação automática
RENEW_CRON="/etc/cron.d/certbot_renew"
if [[ ! -f $RENEW_CRON ]]; then
  echo "0 2 * * * root certbot renew --quiet --deploy-hook 'systemctl reload nginx'" \
    > "$RENEW_CRON"
  chmod 644 "$RENEW_CRON"
  info "Cron diário de renovação criado em $RENEW_CRON"
fi

#-----------------------------------------------------------------------------
# 7) Conclusão
#-----------------------------------------------------------------------------
echo -e "\n\033[1;32mInstalação concluída com sucesso!\033[0m"
echo " • Chatwoot:  https://${CHAT_DOMAIN}"
echo " • WAHA:      https://${WAHA_DOMAIN}"
echo " • n8n:       https://${N8N_DOMAIN}"
echo "Entre no WAHA, leia o QR code do WhatsApp, depois crie os fluxos no n8n."
