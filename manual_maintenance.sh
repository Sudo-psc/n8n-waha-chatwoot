#!/usr/bin/env bash
# Atualiza imagens Docker, renova certificados SSL e valida HTTPS

set -Eeuo pipefail
trap 'echo "[ERRO] Linha $LINENO: comando \"$BASH_COMMAND\" falhou" >&2' ERR

log() { echo -e "\e[36m[MANUT]\e[0m $*"; }

[[ $EUID -eq 0 ]] || { echo "[ERRO] Rode como root"; exit 1; }

declare -a DEPS=(docker certbot curl openssl)
log "Verificando dependências..."
for dep in "${DEPS[@]}"; do
  if ! command -v "$dep" &>/dev/null; then
    echo "[ERRO] Dependência '$dep' não encontrada" >&2
    exit 1
  fi
  case "$dep" in
    openssl) openssl version ;;
    *) "$dep" --version | head -n1 ;;
  esac
done

# Domínios utilizados nos testes
DOMAINS=(
  "chat.example.com"
  "waha.example.com"
  "n8n.example.com"
)

# Verifica validade do certificado SSL de um domínio
check_cert() {
  local domain=$1
  if expiry=$(openssl s_client -connect "$domain:443" -servername "$domain" -CAfile /etc/ssl/certs/ca-certificates.crt </dev/null 2>/dev/null \
    | openssl x509 -noout -enddate); then
    log "Certificado de $domain expira em ${expiry#*=}"
  else
    log "[ERRO] Falha ao validar certificado de $domain"
  fi
}

# Testa acesso HTTPS de um domínio
test_https() {
  local domain=$1
  local url="https://$domain"
  local code
  code=$(curl -ks -o /dev/null -w '%{http_code}' "$url" || true)
  log "$url -> HTTP $code"
}

log "Atualizando containers Docker..."
for compose in /opt/chatwoot/docker-compose.yml \
               /opt/waha/docker-compose.yml \
               /opt/n8n/docker-compose.yml; do
  [[ -f "$compose" ]] || continue
  name=$(basename "$(dirname "$compose")")
  log "Atualizando $name..."
  docker compose -f "$compose" pull
  docker compose -f "$compose" up -d
done

log "Renovando certificados SSL..."
certbot renew --quiet
systemctl reload nginx

log "Validando certificados e HTTPS..."
for domain in "${DOMAINS[@]}"; do
  check_cert "$domain"
  test_https "$domain"
done

log "Manutenção concluída."
