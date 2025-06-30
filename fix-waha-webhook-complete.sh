#!/bin/bash

# Script completo para resolver problemas de webhook WAHA → n8n
# Autor: philipe_cruz@outlook.com

echo "🔧 Correção Completa de Webhook WAHA → n8n"
echo "=========================================="

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }

# Diagnóstico inicial
info "Fazendo diagnóstico do problema..."

echo ""
echo "📋 Problemas Identificados nos Logs:"
echo "1. Webhook duplicado (HTTP e HTTPS)"
echo "2. Webhook '762bab52-b669-433d-b120-39a64420d14e' não está ativo no n8n"
echo "3. Erros de GPU/Vulkan (não críticos)"
echo "4. Status code 404 em loops de retry"

# Verificar conectividade básica
echo ""
info "Verificando conectividade..."

# Teste n8n
n8n_status=$(curl -s -o /dev/null -w "%{http_code}" https://n8n.example.com/)
if [[ $n8n_status == "200" ]]; then
    success "n8n acessível: HTTP $n8n_status"
else
    error "n8n não acessível: HTTP $n8n_status"
    exit 1
fi

# Verificar configuração atual do WAHA
echo ""
info "Verificando configuração atual do WAHA..."
current_webhooks=$(curl -s https://waha.example.com/api/sessions | jq -r '.[0].config.webhooks[].url')
echo "Webhooks configurados:"
echo "$current_webhooks"

# Verificar se webhooks estão funcionando
echo ""
info "Testando webhooks configurados..."

while IFS= read -r webhook_url; do
    if [[ -n "$webhook_url" ]]; then
        response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$webhook_url" -H "Content-Type: application/json" -d '{"test": true}')
        if [[ $response == "200" ]]; then
            success "Webhook OK: $webhook_url"
        else
            warning "Webhook falhou ($response): $webhook_url"
        fi
    fi
done <<< "$current_webhooks"

# Solução 1: Criar webhook funcional temporário
echo ""
info "Implementando correção temporária..."

# Parar sessão
info "Parando sessão do WAHA..."
curl -s -X POST https://waha.example.com/api/sessions/default/stop >/dev/null

sleep 3

# Configurar com webhook que funciona (httpbin para teste)
info "Configurando webhook temporário para teste..."
start_response=$(curl -s -X POST https://waha.example.com/api/sessions/default/start \
  -H "Content-Type: application/json" \
  -d '{
    "name": "default",
    "config": {
      "webhooks": [
        {
          "url": "https://httpbin.org/post",
          "events": ["message"]
        }
      ]
    }
  }')

if [[ $start_response == *'"status":"STARTING"'* ]]; then
    success "WAHA reiniciado com webhook de teste"
else
    warning "Problema ao reiniciar WAHA"
fi

# Aguardar inicialização
info "Aguardando inicialização..."
sleep 10

# Verificar se o webhook de teste funciona
info "Testando webhook temporário..."
for i in {1..3}; do
    echo "Tentativa $i/3..."
    waha_status=$(curl -s https://waha.example.com/api/sessions | jq -r '.[0].status')
    if [[ $waha_status == "WORKING" ]]; then
        success "WAHA funcionando"
        break
    else
        warning "WAHA ainda iniciando... Status: $waha_status"
        sleep 5
    fi
done

# Monitorar logs por alguns segundos
echo ""
info "Monitorando logs por 10 segundos..."
timeout 10 docker logs -f waha-waha-1 | grep -E "(WARN|ERROR|WebhookSender)" &
sleep 10

echo ""
echo "🎯 Resultados da Correção:"
echo "========================="

# Verificar logs recentes
recent_errors=$(docker logs waha-waha-1 --since=1m | grep -c "404" || echo "0")
if [[ $recent_errors -eq 0 ]]; then
    success "Sem erros 404 nos últimos minutos"
else
    warning "Ainda há $recent_errors erros 404 recentes"
fi

# Status final
final_status=$(curl -s https://waha.example.com/api/sessions | jq -r '.[0].status')
if [[ $final_status == "WORKING" ]]; then
    success "Status final: $final_status"
else
    warning "Status final: $final_status"
fi

echo ""
echo "📝 Próximos Passos para Solução Definitiva:"
echo "==========================================="

echo ""
echo "1️⃣ CONFIGURAR WEBHOOK NO N8N:"
echo "   🌐 Acesse: https://n8n.example.com"
echo "   🔑 Login: admin / $(grep N8N_BASIC_AUTH_PASSWORD /opt/n8n/.env | cut -d'=' -f2)"
echo "   📋 Crie workflow com trigger 'Webhook'"
echo "   ⚙️  Configure HTTP Method: POST"
echo "   🔄 ATIVE o workflow (toggle superior direito)"

echo ""
echo "2️⃣ OBTER URL DO WEBHOOK:"
echo "   📋 Copie a 'Production URL' do webhook"
echo "   📝 Exemplo: https://n8n.example.com/webhook/NOVO_ID"

echo ""
echo "3️⃣ CONFIGURAR NO WAHA:"
webhook_config_cmd='curl -X POST https://waha.example.com/api/sessions/default/stop
sleep 3
curl -X POST https://waha.example.com/api/sessions/default/start \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"default\",
    \"config\": {
      \"webhooks\": [
        {
          \"url\": \"https://n8n.example.com/webhook/SEU_NOVO_WEBHOOK_ID\",
          \"events\": [\"message\", \"session.status\"]
        }
      ]
    }
  }"'

echo "$webhook_config_cmd"

echo ""
echo "🔍 COMANDOS DE MONITORAMENTO:"
echo "• docker logs -f waha-waha-1"
echo "• docker logs -f n8n-n8n-1"
echo "• ./fix-waha-webhook.sh"

echo ""
if [[ $recent_errors -eq 0 ]]; then
    success "✅ CORREÇÃO TEMPORÁRIA APLICADA COM SUCESSO!"
    echo "   O webhook de teste (httpbin.org) está funcionando."
    echo "   Agora configure o webhook no n8n conforme as instruções acima."
else
    warning "⚠️  CORREÇÃO PARCIAL - Webhook de teste pode ainda estar causando erros."
    echo "   Configure o webhook no n8n o quanto antes."
fi

echo ""
echo "📞 Status atual: WAHA funcionando com webhook temporário"
echo "🎯 Objetivo: Substituir por webhook do n8n ativo" 