# 🔐 Credenciais de Acesso aos Serviços

## 🌐 URLs de Acesso

### Chatwoot
- **URL:** https://chat.saraivavision.com.br
- **Tipo de autenticação:** Sistema próprio (criar conta no primeiro acesso)

### WAHA (WhatsApp HTTP API)
- **URL:** https://waha.saraivavision.com.br
- **Dashboard:** 
  - Usuário: `admin`
  - Senha: `f6d0bac9060286beeab58768`
- **Swagger API:**
  - Usuário: `api`
  - Senha: `b6759f8e45187bd1ec167268`

### n8n
- **URL:** https://n8n.saraivavision.com.br
- **Usuário:** `admin`
- **Senha:** `5086781ce4cdfb704954a03d`

## ⚠️ Importante

1. **Sempre use HTTPS** - os links HTTP redirecionam automaticamente
2. **Use os domínios**, não o IP direto (31.97.129.78)
3. Se aparecer erro de conexão, limpe o cache do navegador
4. Para problemas de acesso, tente uma aba anônima/privada

## 🔄 Como verificar/alterar credenciais

As credenciais estão armazenadas em:
- Chatwoot: Gerenciado pelo próprio sistema
- WAHA: `/opt/waha/.env`
- n8n: `/opt/n8n/.env`

Para alterar, edite o arquivo `.env` correspondente e reinicie o container:
```bash
cd /opt/[serviço]
docker compose restart
``` 