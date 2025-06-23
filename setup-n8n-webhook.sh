#!/bin/bash

# Script para configurar webhook n8n para WAHA
# Autor: philipe_cruz@outlook.com

echo "🔧 Configuração de Webhook n8n para WAHA"
echo "========================================"

# Verificar acesso ao n8n
echo ""
echo "📋 Verificando acesso ao n8n:"
n8n_status=$(curl -s -o /dev/null -w "%{http_code}" https://n8n.saraivavision.com.br/)
if [[ $n8n_status == "200" ]]; then
    echo "✅ n8n acessível: HTTP $n8n_status"
else
    echo "❌ n8n não acessível: HTTP $n8n_status"
    exit 1
fi

echo ""
echo "🔍 Problema Identificado:"
echo "O webhook atual não está ativo no n8n."
echo "Logs mostram: 'The requested webhook is not registered'"

echo ""
echo "📝 Instruções para Resolver:"
echo ""
echo "1️⃣ Acesse o n8n:"
echo "   🌐 https://n8n.saraivavision.com.br"
echo ""
echo "2️⃣ Faça login no n8n (se necessário):"
echo "   • Usuário: admin"
echo "   • Senha: (verificar em /opt/n8n/.env)"

# Mostrar credenciais do n8n
echo ""
echo "🔑 Credenciais do n8n:"
if [[ -f /opt/n8n/.env ]]; then
    echo "   • Usuário: $(grep N8N_BASIC_AUTH_USER /opt/n8n/.env | cut -d'=' -f2)"
    echo "   • Senha: $(grep N8N_BASIC_AUTH_PASSWORD /opt/n8n/.env | cut -d'=' -f2)"
else
    echo "   ⚠️  Arquivo .env não encontrado"
fi

echo ""
echo "3️⃣ Criar um novo workflow:"
echo "   • Clique em 'New Workflow'"
echo "   • Adicione um trigger 'Webhook'"
echo "   • Configure o Webhook:"
echo "     - HTTP Method: POST"
echo "     - Path: waha-messages (ou qualquer nome)"
echo "   • Adicione nós para processar mensagens"
echo "   • IMPORTANTE: Ative o workflow (toggle no canto superior direito)"

echo ""
echo "4️⃣ Copiar URL do webhook:"
echo "   • No nó webhook, copie a 'Production URL'"
echo "   • Deve ser algo como:"
echo "     https://n8n.saraivavision.com.br/webhook/waha-messages"

echo ""
echo "5️⃣ Configurar no WAHA:"
webhook_commands='
# Parar a sessão atual
curl -X POST https://waha.saraivavision.com.br/api/sessions/default/stop

# Iniciar com novo webhook
curl -X POST https://waha.saraivavision.com.br/api/sessions/default/start \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"default\",
    \"config\": {
      \"webhooks\": [
        {
          \"url\": \"https://n8n.saraivavision.com.br/webhook/NOME_DO_SEU_WEBHOOK\",
          \"events\": [\"message\", \"session.status\"]
        }
      ]
    }
  }"
'

echo "$webhook_commands"

echo ""
echo "🧪 Testar webhook:"
echo "Após configurar, teste com:"
echo "curl -X POST https://n8n.saraivavision.com.br/webhook/SEU_WEBHOOK \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"test\": \"mensagem de teste\"}'"

echo ""
echo "📊 Monitorar logs:"
echo "• WAHA: docker logs -f waha-waha-1"
echo "• n8n:  docker logs -f n8n-n8n-1"

echo ""
echo "💡 Exemplo de Workflow simples no n8n:"
echo "1. Webhook (trigger) → recebe mensagens do WAHA"
echo "2. Code/Function → processa mensagem"
echo "3. HTTP Request → envia para Chatwoot ou outro serviço"

echo ""
echo "🔧 URLs importantes:"
echo "• n8n Dashboard: https://n8n.saraivavision.com.br"
echo "• WAHA Dashboard: https://waha.saraivavision.com.br/dashboard"
echo "• WAHA API: https://waha.saraivavision.com.br"

echo ""
echo "✅ Conectividade WAHA ↔ n8n já está funcionando!"
echo "⚠️  Apenas falta ativar o webhook no n8n." 