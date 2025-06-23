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

# Teste 2: Recursos JavaScript
echo "2️⃣ Testando recursos JavaScript..."
js_response=$(curl -s -o /dev/null -w "%{http_code}" https://chat.saraivavision.com.br/vite/assets/dashboard-BPcVpBrL.js)
if [ "$js_response" = "200" ]; then
    echo "✅ JavaScript: OK (HTTP $js_response)"
else
    echo "❌ JavaScript: ERRO (HTTP $js_response)"
fi

# Teste 3: Recursos CSS
echo "3️⃣ Testando recursos CSS..."
css_response=$(curl -s -o /dev/null -w "%{http_code}" https://chat.saraivavision.com.br/vite/assets/dashboard-nJnDTnT0.css)
if [ "$css_response" = "200" ]; then
    echo "✅ CSS: OK (HTTP $css_response)"
else
    echo "❌ CSS: ERRO (HTTP $css_response)"
fi

# Teste 4: API do Chatwoot
echo "4️⃣ Testando API do Chatwoot..."
api_response=$(curl -s -o /dev/null -w "%{http_code}" https://chat.saraivavision.com.br/api/v1/accounts)
if [ "$api_response" = "401" ] || [ "$api_response" = "200" ]; then
    echo "✅ API: OK (HTTP $api_response - esperado 401 sem autenticação)"
else
    echo "❌ API: ERRO (HTTP $api_response)"
fi

# Teste 5: Redirecionamento HTTP para HTTPS
echo "5️⃣ Testando redirecionamento HTTP → HTTPS..."
redirect_response=$(curl -s -o /dev/null -w "%{http_code}" http://chat.saraivavision.com.br/)
if [ "$redirect_response" = "301" ]; then
    echo "✅ Redirecionamento: OK (HTTP $redirect_response)"
else
    echo "❌ Redirecionamento: ERRO (HTTP $redirect_response)"
fi

# Teste 6: Verificação de cabeçalhos de segurança
echo "6️⃣ Verificando cabeçalhos de segurança..."
headers=$(curl -s -I https://chat.saraivavision.com.br/ | grep -E "(Content-Security-Policy|X-Frame-Options|Strict-Transport-Security)")
if [[ $headers == *"Content-Security-Policy"* ]]; then
    echo "✅ Content-Security-Policy: Configurado"
else
    echo "❌ Content-Security-Policy: Não encontrado"
fi

# Teste 7: Container Docker
echo "7️⃣ Verificando container Docker..."
container_status=$(docker ps --filter "name=chatwoot-rails-1" --format "{{.Status}}")
if [[ $container_status == *"Up"* ]]; then
    echo "✅ Container: Running ($container_status)"
else
    echo "❌ Container: Problema ($container_status)"
fi

echo ""
echo "🎯 Teste completo finalizado!"
echo "Agora você pode testar manualmente no navegador:"
echo "🌐 https://chat.saraivavision.com.br/" 