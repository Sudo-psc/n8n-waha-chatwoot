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
css_response=$(curl -s -o /dev/null -w "%{http_code}" https://waha.saraivavision.com.br/dashboard/_nuxt/entry.BTNZ7KvC.css)
if [ "$css_response" = "200" ]; then
    echo "✅ CSS: OK (HTTP $css_response)"
else
    echo "❌ CSS: ERRO (HTTP $css_response)"
fi

# Teste 3: Recursos JavaScript
echo "3️⃣ Testando recursos JavaScript..."
js_response=$(curl -s -o /dev/null -w "%{http_code}" https://waha.saraivavision.com.br/dashboard/_nuxt/3wcKxrOr.js)
if [ "$js_response" = "200" ]; then
    echo "✅ JavaScript: OK (HTTP $js_response)"
else
    echo "❌ JavaScript: ERRO (HTTP $js_response)"
fi

# Teste 4: Favicon
echo "4️⃣ Testando favicon..."
favicon_response=$(curl -s -o /dev/null -w "%{http_code}" https://waha.saraivavision.com.br/dashboard/favicon.ico)
if [ "$favicon_response" = "200" ]; then
    echo "✅ Favicon: OK (HTTP $favicon_response)"
else
    echo "❌ Favicon: ERRO (HTTP $favicon_response)"
fi

# Teste 5: API do WAHA
echo "5️⃣ Testando API do WAHA..."
api_response=$(curl -s -o /dev/null -w "%{http_code}" https://waha.saraivavision.com.br/api/sessions)
if [ "$api_response" = "200" ]; then
    echo "✅ API: OK (HTTP $api_response)"
else
    echo "❌ API: ERRO (HTTP $api_response)"
fi

# Teste 6: Verificação de cabeçalhos de segurança
echo "6️⃣ Verificando cabeçalhos de segurança..."
headers=$(curl -s -I https://waha.saraivavision.com.br/dashboard/ | grep -E "(Content-Security-Policy|X-Frame-Options|Strict-Transport-Security)")
if [[ $headers == *"Content-Security-Policy"* ]]; then
    echo "✅ Content-Security-Policy: Configurado"
else
    echo "❌ Content-Security-Policy: Não encontrado"
fi

echo ""
echo "🎯 Teste completo finalizado!"
echo "Agora você pode testar manualmente no navegador:"
echo "🌐 https://waha.saraivavision.com.br/dashboard/" 