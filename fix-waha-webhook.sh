#!/bin/bash

# Script para corrigir problemas de webhook entre WAHA e n8n
# Autor: philipe_cruz@outlook.com

echo "🔧 Diagnóstico e Correção de Webhook WAHA → n8n"
echo "================================================"

# Verificar status atual dos webhooks
echo ""
echo "📋 Status Atual dos Webhooks no WAHA:"
waha_webhooks=$(curl -s https://waha.saraivavision.com.br/api/sessions | jq -r '.[0].config.webhooks[].url')
echo "$waha_webhooks"

echo ""
echo "🧪 Testando Conectividade:"

# Teste de conectividade básica com n8n
n8n_status=$(curl -s -o /dev/null -w "%{http_code}" https://n8n.saraivavision.com.br/)
if [[ $n8n_status == "200" ]] || [[ $n8n_status == "401" ]]; then
    echo "✅ n8n acessível: HTTP $n8n_status"
else
    echo "❌ n8n não acessível: HTTP $n8n_status"
    exit 1
fi

echo ""
echo "🔍 Analisando Webhooks Configurados:"

# Para cada webhook configurado no WAHA
curl -s https://waha.saraivavision.com.br/api/sessions | jq -r '.[0].config.webhooks[].url' | while read webhook_url; do
    if [[ -n "$webhook_url" ]]; then
        echo ""
        echo "📍 Testando: $webhook_url"
        
        # Teste GET
        get_response=$(curl -s -o /dev/null -w "%{http_code}" "$webhook_url")
        if [[ $get_response == "200" ]]; then
            echo "  ✅ GET: OK ($get_response)"
        else
            echo "  ❌ GET: Erro ($get_response)"
        fi
        
        # Teste POST
        post_response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$webhook_url" -H "Content-Type: application/json" -d '{"test": true}')
        if [[ $post_response == "200" ]]; then
            echo "  ✅ POST: OK ($post_response)"
        else
            echo "  ❌ POST: Erro ($post_response)"
            
            # Verificar se é erro 404 específico do n8n
            post_message=$(curl -s -X POST "$webhook_url" -H "Content-Type: application/json" -d '{"test": true}')
            if [[ $post_message == *"not registered for POST"* ]]; then
                echo "    🔧 Causa: Webhook configurado apenas para GET no n8n"
            fi
        fi
    fi
done

echo ""
echo "💡 Soluções Recomendadas:"
echo "========================="

echo ""
echo "📝 Para corrigir o problema de webhook:"
echo ""
echo "1️⃣ Opção 1 - Reconfigurar o webhook no n8n:"
echo "   • Acesse: https://n8n.saraivavision.com.br"
echo "   • Edite o workflow que usa este webhook"
echo "   • Configure o trigger de webhook para aceitar POST"
echo "   • Ou use 'Webhook' em vez de 'Webhook (for testing)'"
echo ""
echo "2️⃣ Opção 2 - Criar novo webhook no n8n:"
echo "   • Crie um novo workflow no n8n"
echo "   • Use trigger 'Webhook' (não 'Webhook for testing')"
echo "   • Configure para aceitar POST"
echo "   • Copie a nova URL e atualize no WAHA"
echo ""
echo "3️⃣ Opção 3 - Comando para gerar novo webhook:"
echo "   curl -X POST https://waha.saraivavision.com.br/api/sessions/default/webhooks \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"url\": \"NOVA_URL_DO_WEBHOOK\", \"events\": [\"message\"]}'"

echo ""
echo "🎯 Status da Correção de Conectividade:"
echo "✅ RESOLVIDO: WAHA agora conecta com n8n via HTTPS"
echo "✅ RESOLVIDO: Removida porta :5678 incorreta"
echo "⚠️  PENDENTE: Configurar webhook no n8n para aceitar POST"

echo ""
echo "📞 Logs do WAHA agora mostram HTTP 404 em vez de ECONNREFUSED"
echo "   Isso confirma que a conectividade está funcionando!"

# Oferecer monitoramento em tempo real
echo ""
echo "🔍 Para monitorar logs do WAHA em tempo real:"
echo "docker logs -f waha-waha-1" 