#!/usr/bin/env bash
###############################################################################
# Script de Diagnóstico SSL e Roteamento HTTPS
# Verifica certificados, configurações Nginx, DNS e conectividade
###############################################################################

set -Eeuo pipefail
trap 'echo -e "\e[31m[ERRO] Linha $LINENO: comando \"$BASH_COMMAND\" falhou\e[0m" >&2' ERR

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging
log() { echo -e "${CYAN}[DIAG]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warning() { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; }
info() { echo -e "${BLUE}[i]${NC} $*"; }

# Verificação de root
[[ $EUID -eq 0 ]] || { error "Execute como root (sudo)"; exit 1; }

# Domínios para verificar
DOMAINS=(
  "chat.saraivavision.com.br"
  "waha.saraivavision.com.br"
  "n8n.saraivavision.com.br"
)

# Portas dos serviços
declare -A SERVICE_PORTS=(
  ["chat.saraivavision.com.br"]="3000"
  ["waha.saraivavision.com.br"]="3001"
  ["n8n.saraivavision.com.br"]="3002"
)

echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}       DIAGNÓSTICO SSL E ROTEAMENTO HTTPS${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"

# 1. Verificar serviços essenciais
log "Verificando serviços essenciais..."
echo ""

# Nginx
if systemctl is-active --quiet nginx; then
    success "Nginx está rodando"
    nginx_version=$(nginx -v 2>&1 | cut -d' ' -f3 | cut -d'/' -f2)
    info "Versão: nginx/$nginx_version"
else
    error "Nginx não está rodando!"
    systemctl status nginx --no-pager | head -10
fi

# Docker
if systemctl is-active --quiet docker; then
    success "Docker está rodando"
    docker_version=$(docker --version | cut -d' ' -f3 | tr -d ',')
    info "Versão: Docker $docker_version"
else
    error "Docker não está rodando!"
fi

echo -e "\n${CYAN}─────────────────────────────────────────────────────────${NC}"
log "Verificando containers Docker..."
echo ""

for domain in "${!SERVICE_PORTS[@]}"; do
    service_name=$(echo "$domain" | cut -d'.' -f1)
    port="${SERVICE_PORTS[$domain]}"
    
    # Verificar se o container está rodando
    if docker ps | grep -q "$service_name"; then
        success "Container $service_name está rodando"
        
        # Verificar se a porta está sendo escutada
        if ss -tuln | grep -q ":$port "; then
            success "Porta $port está escutando"
        else
            error "Porta $port não está escutando!"
        fi
    else
        error "Container $service_name não está rodando!"
    fi
done

echo -e "\n${CYAN}─────────────────────────────────────────────────────────${NC}"
log "Verificando resolução DNS..."
echo ""

# Obter IP público do servidor
PUBLIC_IP=$(curl -s -4 https://icanhazip.com 2>/dev/null || echo "N/A")
info "IP público do servidor: $PUBLIC_IP"
echo ""

for domain in "${DOMAINS[@]}"; do
    echo -e "${BLUE}Domínio: $domain${NC}"
    
    # Verificar resolução DNS
    if resolved_ip=$(dig +short "$domain" @8.8.8.8 2>/dev/null | tail -1); then
        if [[ -n "$resolved_ip" ]]; then
            info "Resolvido para: $resolved_ip"
            
            if [[ "$resolved_ip" == "$PUBLIC_IP" ]]; then
                success "DNS aponta corretamente para este servidor"
            else
                warning "DNS aponta para IP diferente do servidor!"
            fi
        else
            error "Falha na resolução DNS"
        fi
    else
        error "Erro ao consultar DNS"
    fi
    echo ""
done

echo -e "\n${CYAN}─────────────────────────────────────────────────────────${NC}"
log "Analisando certificados SSL..."
echo ""

for domain in "${DOMAINS[@]}"; do
    echo -e "${BLUE}Certificado para: $domain${NC}"
    
    cert_file="/etc/letsencrypt/live/$domain/fullchain.pem"
    if [[ -f "$cert_file" ]]; then
        success "Arquivo de certificado existe"
        
        # Verificar validade
        if openssl x509 -checkend 86400 -noout -in "$cert_file" 2>/dev/null; then
            success "Certificado válido (não expira nas próximas 24h)"
            
            # Mostrar detalhes
            expiry=$(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)
            info "Expira em: $expiry"
            
            # Verificar CN e SANs
            subject=$(openssl x509 -subject -noout -in "$cert_file" | cut -d= -f2-)
            info "Subject: $subject"
        else
            error "Certificado expirado ou expirando em breve!"
        fi
    else
        error "Arquivo de certificado não encontrado!"
    fi
    echo ""
done

echo -e "\n${CYAN}─────────────────────────────────────────────────────────${NC}"
log "Verificando configurações Nginx..."
echo ""

# Testar configuração
if nginx -t 2>/dev/null; then
    success "Configuração Nginx é válida"
else
    error "Erro na configuração Nginx!"
    nginx -t
fi

# Verificar sites habilitados
echo -e "\n${BLUE}Sites habilitados:${NC}"
for domain in "${DOMAINS[@]}"; do
    if [[ -L "/etc/nginx/sites-enabled/$domain" ]]; then
        success "$domain está habilitado"
        
        # Verificar se tem configuração SSL
        if grep -q "listen 443 ssl" "/etc/nginx/sites-available/$domain" 2>/dev/null || \
           grep -q "listen \[::\]:443 ssl" "/etc/nginx/sites-available/$domain" 2>/dev/null; then
            success "SSL configurado para $domain"
        else
            warning "SSL pode não estar configurado corretamente"
        fi
    else
        error "$domain não está habilitado!"
    fi
done

echo -e "\n${CYAN}─────────────────────────────────────────────────────────${NC}"
log "Testando conectividade HTTPS..."
echo ""

# Testes de conectividade local
echo -e "${BLUE}Testes locais (do servidor):${NC}"
for domain in "${DOMAINS[@]}"; do
    echo -e "\n${CYAN}$domain:${NC}"
    
    # Teste HTTP
    if http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://$domain" 2>/dev/null); then
        if [[ "$http_code" == "301" ]] || [[ "$http_code" == "302" ]]; then
            success "HTTP redireciona (código $http_code)"
        else
            warning "HTTP retorna código $http_code"
        fi
    else
        error "Falha no teste HTTP"
    fi
    
    # Teste HTTPS
    if https_code=$(curl -s -o /dev/null -w "%{http_code}" "https://$domain" 2>/dev/null); then
        if [[ "$https_code" == "200" ]]; then
            success "HTTPS responde com sucesso (200)"
        else
            warning "HTTPS retorna código $https_code"
        fi
    else
        error "Falha no teste HTTPS"
    fi
    
    # Verificar certificado via openssl
    echo -e "\n  ${CYAN}Verificação SSL:${NC}"
    if echo | timeout 5 openssl s_client -connect "$domain:443" -servername "$domain" 2>/dev/null | \
       openssl x509 -noout 2>/dev/null; then
        success "Certificado SSL acessível"
        
        # Verificar chain
        chain_info=$(echo | timeout 5 openssl s_client -connect "$domain:443" -servername "$domain" 2>&1 | \
                     grep -E "verify return:|Verify return code:")
        if echo "$chain_info" | grep -q "Verify return code: 0"; then
            success "Chain de certificados válido"
        else
            warning "Possível problema no chain: $chain_info"
        fi
    else
        error "Não foi possível verificar certificado SSL"
    fi
done

echo -e "\n${CYAN}─────────────────────────────────────────────────────────${NC}"
log "Verificando portas e firewall..."
echo ""

# Verificar portas abertas
echo -e "${BLUE}Portas escutando:${NC}"
ss -tuln | grep -E ":(80|443|3000|3001|3002) " | while read -r line; do
    info "$line"
done

# Verificar regras iptables
echo -e "\n${BLUE}Regras de firewall (iptables):${NC}"
if iptables -L INPUT -n | grep -E "(80|443)" >/dev/null 2>&1; then
    success "Regras para portas 80/443 encontradas"
else
    warning "Nenhuma regra específica para 80/443 no iptables"
fi

# Verificar ufw se estiver instalado
if command -v ufw &>/dev/null; then
    echo -e "\n${BLUE}Status UFW:${NC}"
    if ufw status | grep -q "Status: active"; then
        info "UFW está ativo"
        ufw status numbered | grep -E "(80|443|Nginx)" | while read -r line; do
            info "$line"
        done
    else
        info "UFW não está ativo"
    fi
fi

echo -e "\n${CYAN}─────────────────────────────────────────────────────────${NC}"
log "Verificando logs de erro..."
echo ""

# Verificar logs do Nginx
if [[ -f /var/log/nginx/error.log ]]; then
    echo -e "${BLUE}Últimos erros do Nginx:${NC}"
    tail -5 /var/log/nginx/error.log | while read -r line; do
        if [[ -n "$line" ]]; then
            warning "$line"
        fi
    done
else
    info "Log de erros do Nginx não encontrado"
fi

echo -e "\n${CYAN}─────────────────────────────────────────────────────────${NC}"
log "Teste de conectividade externa..."
echo ""

# Usar um serviço externo para verificar HTTPS
echo -e "${BLUE}Verificando acessibilidade externa:${NC}"
for domain in "${DOMAINS[@]}"; do
    echo -e "\n${CYAN}$domain:${NC}"
    
    # Teste via serviço externo
    if ext_result=$(curl -s "https://api.hackertarget.com/httpheaders/?q=https://$domain" 2>/dev/null | head -1); then
        if [[ "$ext_result" == *"200 OK"* ]]; then
            success "Acessível externamente com HTTPS"
        elif [[ "$ext_result" == *"301"* ]] || [[ "$ext_result" == *"302"* ]]; then
            info "Redirecionamento detectado externamente"
        else
            warning "Resposta externa: $ext_result"
        fi
    else
        error "Não foi possível verificar acesso externo"
    fi
done

echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"
log "Resumo do diagnóstico"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"

# Contar problemas
problems=0
warnings=0

# Verificar cada domínio
for domain in "${DOMAINS[@]}"; do
    echo -e "${BLUE}$domain:${NC}"
    
    # DNS
    if resolved_ip=$(dig +short "$domain" @8.8.8.8 2>/dev/null | tail -1); then
        if [[ "$resolved_ip" == "$PUBLIC_IP" ]]; then
            success "DNS ✓"
        else
            error "DNS ✗"
            ((problems++))
        fi
    fi
    
    # Certificado
    if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
        if openssl x509 -checkend 86400 -noout -in "/etc/letsencrypt/live/$domain/fullchain.pem" 2>/dev/null; then
            success "Certificado ✓"
        else
            error "Certificado ✗"
            ((problems++))
        fi
    else
        error "Certificado ✗"
        ((problems++))
    fi
    
    # HTTPS
    if https_code=$(curl -s -o /dev/null -w "%{http_code}" "https://$domain" 2>/dev/null); then
        if [[ "$https_code" == "200" ]]; then
            success "HTTPS ✓"
        else
            warning "HTTPS ! (código $https_code)"
            ((warnings++))
        fi
    else
        error "HTTPS ✗"
        ((problems++))
    fi
    
    echo ""
done

if [[ $problems -eq 0 ]]; then
    echo -e "\n${GREEN}✓ Nenhum problema crítico encontrado!${NC}"
else
    echo -e "\n${RED}✗ $problems problema(s) crítico(s) encontrado(s)!${NC}"
fi

if [[ $warnings -gt 0 ]]; then
    echo -e "${YELLOW}! $warnings aviso(s) encontrado(s)${NC}"
fi

echo -e "\n${CYAN}Diagnóstico concluído.${NC}\n" 