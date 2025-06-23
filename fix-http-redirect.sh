#!/usr/bin/env bash
###############################################################################
# Script para corrigir redirecionamento HTTP → HTTPS no Nginx
###############################################################################

set -Eeuo pipefail
trap 'echo -e "\e[31m[ERRO] Linha $LINENO: comando \"$BASH_COMMAND\" falhou\e[0m" >&2' ERR

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${CYAN}[FIX]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warning() { echo -e "${YELLOW}[!]${NC} $*"; }

[[ $EUID -eq 0 ]] || { echo "Execute como root (sudo)"; exit 1; }

DOMAINS=(
  "chat.saraivavision.com.br"
  "waha.saraivavision.com.br"
  "n8n.saraivavision.com.br"
)

# Definir portas dos serviços
declare -A SERVICE_PORTS=(
    ["chat.saraivavision.com.br"]="3000"
    ["waha.saraivavision.com.br"]="3001"
    ["n8n.saraivavision.com.br"]="3002"
)

log "Corrigindo redirecionamento HTTP → HTTPS..."
echo ""

for domain in "${DOMAINS[@]}"; do
    config_file="/etc/nginx/sites-available/$domain"
    
    if [[ ! -f "$config_file" ]]; then
        warning "Arquivo $config_file não encontrado"
        continue
    fi
    
    log "Processando $domain..."
    
    # Fazer backup
    backup_file="${config_file}.bak.$(date +%s)"
    cp "$config_file" "$backup_file"
    success "Backup criado: $backup_file"
    
    # Verificar se já tem redirecionamento
    if grep -q "return 301" "$config_file"; then
        warning "$domain já tem redirecionamento configurado"
        continue
    fi
    
    # Criar nova configuração com redirecionamento
    cat > "$config_file" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    
    # Redirecionar todo tráfego HTTP para HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name $domain;

    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Content-Security-Policy "default-src 'self';" always;
    underscores_in_headers on;

    set \$upstream 127.0.0.1:${SERVICE_PORTS[$domain]};
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
EOF

    success "Configuração atualizada para $domain"
done

# Definir portas dos serviços
declare -A SERVICE_PORTS=(
    ["chat.saraivavision.com.br"]="3000"
    ["waha.saraivavision.com.br"]="3001"
    ["n8n.saraivavision.com.br"]="3002"
)

# Reprocessar com as portas corretas
for domain in "${DOMAINS[@]}"; do
    config_file="/etc/nginx/sites-available/$domain"
    port="${SERVICE_PORTS[$domain]}"
    
    # Substituir a variável pela porta correta
    sed -i "s/\${SERVICE_PORTS\[\$domain\]}/$port/g" "$config_file"
done

log "Testando configuração do Nginx..."
if nginx -t; then
    success "Configuração válida"
    
    log "Recarregando Nginx..."
    systemctl reload nginx
    success "Nginx recarregado com sucesso"
else
    echo -e "\n${RED}[✗] Erro na configuração do Nginx!${NC}"
    echo "Restaure os backups se necessário:"
    for domain in "${DOMAINS[@]}"; do
        echo "  mv /etc/nginx/sites-available/${domain}.bak.* /etc/nginx/sites-available/$domain"
    done
    exit 1
fi

echo ""
log "Testando redirecionamentos..."
echo ""

for domain in "${DOMAINS[@]}"; do
    echo -e "${CYAN}$domain:${NC}"
    
    # Teste de redirecionamento
    if response=$(curl -s -I "http://$domain" | head -1); then
        if [[ "$response" == *"301"* ]] || [[ "$response" == *"302"* ]]; then
            success "HTTP redireciona corretamente"
        else
            warning "Resposta: $response"
        fi
    fi
    
    # Teste HTTPS
    if https_code=$(curl -s -o /dev/null -w "%{http_code}" "https://$domain"); then
        if [[ "$https_code" == "200" ]]; then
            success "HTTPS responde com sucesso (200)"
        else
            warning "HTTPS retorna código $https_code"
        fi
    fi
    echo ""
done

echo -e "${GREEN}✓ Redirecionamento HTTP → HTTPS configurado com sucesso!${NC}" 