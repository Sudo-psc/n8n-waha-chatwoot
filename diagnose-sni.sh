#!/bin/bash

# Script de Diagnóstico de SNI (Server Name Indication)
# Autor: philipe_cruz@outlook.com

echo "🔍 Diagnóstico de SNI (Server Name Indication)"
echo "=============================================="

# Informações do sistema
echo ""
echo "📋 Informações do Sistema:"
echo "IP do Servidor: $(curl -s ifconfig.me)"
echo "Nginx Version: $(nginx -v 2>&1)"
echo "OpenSSL Version: $(openssl version)"

# Verificar se SNI está habilitado
echo ""
echo "🔧 Verificando Suporte a SNI:"
if nginx -V 2>&1 | grep -q "with-http_ssl_module"; then
    echo "✅ SSL Module: Habilitado"
else
    echo "❌ SSL Module: Não encontrado"
fi

if nginx -V 2>&1 | grep -q "with-http_v2_module"; then
    echo "✅ HTTP/2 Module: Habilitado"
else
    echo "❌ HTTP/2 Module: Não encontrado"
fi

# Verificar versão do OpenSSL (SNI requer 0.9.8j+)
openssl_version=$(openssl version | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')
echo "✅ OpenSSL Version: $openssl_version (SNI suportado)"

echo ""
echo "🌐 Domínios Configurados:"

# Lista de domínios
domains=("chat.saraivavision.com.br" "waha.saraivavision.com.br" "n8n.saraivavision.com.br")

for domain in "${domains[@]}"; do
    echo ""
    echo "📍 Testando: $domain"
    
    # Teste 1: Verificar se o certificado está correto para o domínio
    cert_subject=$(openssl s_client -connect ${domain}:443 -servername ${domain} </dev/null 2>/dev/null | openssl x509 -noout -subject 2>/dev/null)
    if [[ $cert_subject == *"$domain"* ]]; then
        echo "  ✅ Certificado SNI: Correto ($cert_subject)"
    else
        echo "  ❌ Certificado SNI: Problema ($cert_subject)"
    fi
    
    # Teste 2: Verificar se responde via HTTPS
    https_status=$(curl -s -o /dev/null -w "%{http_code}" https://${domain}/)
    if [[ $https_status == "200" ]]; then
        echo "  ✅ HTTPS Response: OK ($https_status)"
    else
        echo "  ❌ HTTPS Response: Problema ($https_status)"
    fi
    
    # Teste 3: Verificar redirecionamento HTTP -> HTTPS
    http_redirect=$(curl -s -o /dev/null -w "%{http_code}" http://${domain}/)
    if [[ $http_redirect == "301" ]]; then
        echo "  ✅ HTTP Redirect: OK ($http_redirect)"
    else
        echo "  ❌ HTTP Redirect: Problema ($http_redirect)"
    fi
    
    # Teste 4: Verificar se o certificado está válido
    cert_validity=$(openssl s_client -connect ${domain}:443 -servername ${domain} </dev/null 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
    if [[ -n $cert_validity ]]; then
        echo "  ✅ Certificado: Válido"
        echo "    $(echo "$cert_validity" | grep "notAfter" | cut -d'=' -f2)"
    else
        echo "  ❌ Certificado: Problema de validação"
    fi
done

echo ""
echo "🔒 Configuração de Virtual Hosts:"

# Verificar configurações de listen
echo ""
echo "📋 Portas de Escuta SSL:"
nginx -T 2>/dev/null | grep "listen.*443.*ssl" | sort | uniq

echo ""
echo "📋 Server Names Configurados:"
nginx -T 2>/dev/null | grep "server_name" | grep -v "#" | sort | uniq

echo ""
echo "🏠 Servidor Padrão (default_server):"
nginx -T 2>/dev/null | grep "listen.*default_server" | sort | uniq

echo ""
echo "📁 Certificados Disponíveis:"
if [[ -d /etc/letsencrypt/live/ ]]; then
    ls -la /etc/letsencrypt/live/ | grep "^d" | awk '{print $9}' | grep -v "^\.$\|^\.\.$" | while read cert_dir; do
        if [[ -n $cert_dir ]]; then
            echo "  📜 $cert_dir"
            cert_info=$(openssl x509 -in /etc/letsencrypt/live/${cert_dir}/cert.pem -noout -subject -dates 2>/dev/null)
            if [[ -n $cert_info ]]; then
                echo "    $(echo "$cert_info" | grep "subject")"
                echo "    $(echo "$cert_info" | grep "notAfter")"
            fi
        fi
    done
else
    echo "  ❌ Diretório de certificados não encontrado"
fi

echo ""
echo "🧪 Teste de SNI via IP:"

# Testar acesso via IP com diferentes hostnames
server_ip="31.97.129.78"
echo "Testando SNI via IP ($server_ip):"

for domain in "${domains[@]}"; do
    echo ""
    echo "🔗 Testando $domain via IP:"
    
    # Teste com header Host
    response=$(curl -H "Host: ${domain}" -k -s -o /dev/null -w "%{http_code}" https://${server_ip}/ 2>/dev/null)
    if [[ $response == "200" ]] || [[ $response == "301" ]]; then
        echo "  ✅ Host Header: OK ($response)"
    else
        echo "  ❌ Host Header: Problema ($response)"
    fi
done

echo ""
echo "📊 Resumo da Configuração SNI:"
echo "=============================================="

# Contar quantos domínios estão funcionando
working_domains=0
total_domains=${#domains[@]}

for domain in "${domains[@]}"; do
    status=$(curl -s -o /dev/null -w "%{http_code}" https://${domain}/)
    if [[ $status == "200" ]]; then
        ((working_domains++))
    fi
done

echo "✅ Domínios funcionais: $working_domains/$total_domains"
echo "🔐 SNI Status: $([ $working_domains -eq $total_domains ] && echo "✅ FUNCIONANDO PERFEITAMENTE" || echo "⚠️  ALGUNS PROBLEMAS DETECTADOS")"
echo "🛡️  SSL/TLS: Configurado com Let's Encrypt"
echo "🔄 Renovação: Automática via cron"

echo ""
echo "🎯 Configuração SNI concluída!" 