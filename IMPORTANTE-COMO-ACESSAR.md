# ⚠️ IMPORTANTE: Como Acessar os Serviços

## ❌ ERRO: ERR_SSL_PROTOCOL_ERROR

Se você está vendo o erro **"This site can't provide a secure connection"** ou **"ERR_SSL_PROTOCOL_ERROR"**, é porque você está tentando acessar os serviços pelo IP em vez dos domínios.

### ❌ FORMA ERRADA:
- https://203.0.113.10 ❌
- http://203.0.113.10 ❌

### ✅ FORMA CORRETA:

Use sempre os domínios completos:

- **Chatwoot:** https://chat.example.com ✅
- **WAHA:** https://waha.example.com ✅
- **n8n:** https://n8n.example.com ✅

## 🔍 Por que isso acontece?

1. Os certificados SSL são emitidos para os **domínios específicos**, não para o IP
2. Quando você acessa pelo IP, o navegador detecta que o certificado não corresponde e bloqueia por segurança
3. Isso é um comportamento normal e esperado de segurança SSL/TLS

## 🚀 Solução Implementada

Foi configurado um redirecionamento automático:
- Se você acessar http://203.0.113.10 → será redirecionado para https://chat.example.com
- Se você acessar https://203.0.113.10 → também será redirecionado (mas pode mostrar aviso de segurança primeiro)

## 📝 Dica

Salve os links corretos nos seus favoritos:
- https://chat.example.com
- https://waha.example.com
- https://n8n.example.com

## 🔒 Segurança

Este comportamento é uma **feature de segurança**, não um bug. Garante que você está realmente conectando ao servidor correto e que a conexão está criptografada. 