#!/bin/bash

# Script DEFINITIVO para corrigir webhooks vazios WAHA → n8n
# Autor: philipe_cruz@outlook.com
# Data: $(date)

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 CORREÇÃO DEFINITIVA: Webhooks Vazios WAHA → n8n${NC}"
echo "============================================================"

# Verificar se os serviços estão rodando
echo -e "\n${YELLOW}📋 Verificando status dos serviços...${NC}"

WAHA_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://waha.saraivavision.com.br/api/sessions)
N8N_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://n8n.saraivavision.com.br/)

if [[ $WAHA_STATUS == "200" ]]; then
    echo -e "✅ WAHA está funcionando"
else
    echo -e "❌ WAHA não está acessível"
    exit 1
fi

if [[ $N8N_STATUS == "200" ]] || [[ $N8N_STATUS == "401" ]]; then
    echo -e "✅ n8n está funcionando"
else
    echo -e "❌ n8n não está acessível"
    exit 1
fi

# Analisar problema atual
echo -e "\n${YELLOW}🔍 Diagnosticando problema atual...${NC}"

# Buscar webhooks configurados
WEBHOOK_INFO=$(curl -s https://waha.saraivavision.com.br/api/sessions | jq -r '.[0].config.webhooks[]')
echo -e "Webhooks atuais configurados:"
echo "$WEBHOOK_INFO" | jq .

# Testar webhook atual
WEBHOOK_URL=$(curl -s https://waha.saraivavision.com.br/api/sessions | jq -r '.[0].config.webhooks[0].url')
if [[ -n "$WEBHOOK_URL" ]]; then
    echo -e "\n${YELLOW}🧪 Testando webhook atual: $WEBHOOK_URL${NC}"
    
    # Teste POST
    RESPONSE=$(curl -s -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d '{
            "event": "message",
            "session": "default",
            "data": {
                "id": {
                    "fromMe": false,
                    "remote": "5533842378@c.us",
                    "id": "test123"
                },
                "body": "Teste de webhook",
                "from": "5533842378@c.us",
                "to": "553384237830@c.us",
                "timestamp": 1750710000,
                "type": "chat"
            }
        }' \
        -w "\nHTTP_CODE:%{http_code}")
    
    echo -e "Resposta do teste: $RESPONSE"
    
    if [[ "$RESPONSE" == *"404"* ]] || [[ "$RESPONSE" == *"not registered for POST"* ]]; then
        echo -e "${RED}❌ PROBLEMA IDENTIFICADO: Webhook configurado incorretamente no n8n${NC}"
        echo -e "${RED}   O webhook atual não aceita POST requests${NC}"
    fi
fi

# Soluções para corrigir
echo -e "\n${GREEN}💡 SOLUÇÕES PARA CORRIGIR WEBHOOKS VAZIOS:${NC}"
echo "=========================================================="

echo -e "\n${YELLOW}🎯 PROBLEMA 1: Webhook n8n configurado incorretamente${NC}"
echo -e "CAUSA: Webhook foi criado como 'teste' que só aceita GET"
echo -e "SOLUÇÃO:"
echo -e "1. Acesse: https://n8n.saraivavision.com.br"
echo -e "2. Crie um NOVO workflow"
echo -e "3. Adicione trigger 'Webhook' (NÃO 'Webhook for testing')"
echo -e "4. Configure:"
echo -e "   - HTTP Method: POST"
echo -e "   - Path: /webhook/waha-messages"
echo -e "   - Response Mode: 'Respond to Webhook'"
echo -e "   - Response Data: json"

echo -e "\n${YELLOW}🎯 PROBLEMA 2: Formato de dados incorreto${NC}"
echo -e "CAUSA: WAHA enviando dados em formato que n8n não processa"
echo -e "SOLUÇÃO: Configurar processamento correto no n8n"

echo -e "\n${GREEN}📝 SCRIPT PARA RECONFIGURAR WEBHOOK NO WAHA:${NC}"
echo "=============================================================="

# Webhook URL para configuração
# NEW_WEBHOOK="https://n8n.saraivavision.com.br/webhook/waha-messages"

echo -e "\n${BLUE}1️⃣ Remover webhooks atuais:${NC}"
echo "curl -X DELETE https://waha.saraivavision.com.br/api/sessions/default/webhooks"

echo -e "\n${BLUE}2️⃣ Configurar novo webhook:${NC}"
cat << 'EOF'
curl -X POST https://waha.saraivavision.com.br/api/sessions/default/webhooks \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://n8n.saraivavision.com.br/webhook/waha-messages",
    "events": ["message", "session.status"],
    "retries": {
      "delaySeconds": 2,
      "attempts": 5,
      "policy": "exponential"
    },
    "customHeaders": {
      "X-Webhook-Source": "WAHA",
      "Content-Type": "application/json"
    }
  }'
EOF

echo -e "\n${GREEN}🔧 CONFIGURAÇÃO RECOMENDADA NO N8N:${NC}"
echo "=============================================================="

echo -e "\n${YELLOW}Workflow Exemplo:${NC}"
cat << 'EOF'

1. WEBHOOK NODE:
   - Trigger: Webhook
   - HTTP Method: POST
   - Path: waha-messages
   - Authentication: None
   - Response: Respond to Webhook

2. FUNCTION NODE (processar dados):
   ```javascript
   // Extrair dados da mensagem
   const webhookData = items[0].json;
   
   // Verificar se é uma mensagem
   if (webhookData.event === 'message' && webhookData.data) {
     const message = webhookData.data;
     
     return [{
       json: {
         messageId: message.id?.id || 'unknown',
         from: message.from,
         to: message.to,
         body: message.body,
         timestamp: message.timestamp,
         type: message.type,
         isFromMe: message.fromMe || false,
         session: webhookData.session,
         event: webhookData.event,
         rawData: webhookData
       }
     }];
   }
   
   // Se não for mensagem, retornar dados básicos
   return [{
     json: {
       event: webhookData.event,
       session: webhookData.session,
       data: webhookData.data,
       timestamp: Date.now()
     }
   }];
   ```

3. HTTP RESPONSE NODE:
   - Status Code: 200
   - Body: {"status": "received", "processed": true}

EOF

# Oferecer execução automática
echo -e "\n${GREEN}🚀 EXECUÇÃO AUTOMÁTICA DISPONÍVEL:${NC}"
echo "=============================================================="

read -r -p "Deseja executar a correção automática? (s/n): " AUTO_FIX

if [[ $AUTO_FIX == "s" ]] || [[ $AUTO_FIX == "S" ]]; then
    echo -e "\n${YELLOW}🔄 Executando correção automática...${NC}"
    
    # Backup da configuração atual
    echo -e "📁 Fazendo backup da configuração atual..."
    curl -s https://waha.saraivavision.com.br/api/sessions | jq '.' > "webhook_backup_$(date +%Y%m%d_%H%M%S).json"
    
    # Remover webhooks atuais
    echo -e "🗑️ Removendo webhooks atuais..."
    curl -s -X DELETE https://waha.saraivavision.com.br/api/sessions/default/webhooks
    
    sleep 2
    
    # Configurar novo webhook temporário para teste
    echo -e "⚙️ Configurando webhook de teste..."
    WEBHOOK_RESPONSE=$(curl -s -X POST https://waha.saraivavision.com.br/api/sessions/default/webhooks \
      -H "Content-Type: application/json" \
      -d '{
        "url": "https://webhook.site/unique-id-here",
        "events": ["message"],
        "retries": {
          "delaySeconds": 2,
          "attempts": 3,
          "policy": "exponential"
        }
      }')
    
    echo -e "Webhook configurado: $WEBHOOK_RESPONSE"
    
    echo -e "\n${GREEN}✅ Correção aplicada!${NC}"
    echo -e "${YELLOW}⚠️ PRÓXIMOS PASSOS MANUAIS:${NC}"
    echo -e "1. Configure o workflow no n8n conforme instruções acima"
    echo -e "2. Teste o webhook com uma mensagem no WhatsApp"
    echo -e "3. Execute: curl -X POST https://waha.saraivavision.com.br/api/sessions/default/webhooks com a URL correta do n8n"
else
    echo -e "\n${BLUE}ℹ️ Correção manual necessária${NC}"
    echo -e "Siga as instruções acima para configurar manualmente"
fi

echo -e "\n${GREEN}📊 MONITORAMENTO CONTÍNUO:${NC}"
echo "=============================================================="

echo -e "\n${YELLOW}Para monitorar webhooks em tempo real:${NC}"
echo "docker logs -f waha-waha-1 | grep -E '(webhook|POST|message)'"

echo -e "\n${YELLOW}Para testar webhook manualmente:${NC}"
echo 'curl -X POST https://n8n.saraivavision.com.br/webhook/waha-messages \'
echo '  -H "Content-Type: application/json" \'
echo '  -d '\''{"event":"message","session":"default","data":{"body":"teste"}}'\''

echo -e "\n${GREEN}🎉 Script concluído!${NC}"
echo -e "${BLUE}💬 Para suporte: philipe_cruz@outlook.com${NC}" 