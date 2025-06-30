# 🔐 Credenciais de Acesso aos Serviços

## 🌐 URLs de Acesso

### Chatwoot
- **URL:** https://chat.example.com
- **Tipo de autenticação:** Sistema próprio (criar conta no primeiro acesso)

### WAHA (WhatsApp HTTP API)
- **URL:** https://waha.example.com
 - **Dashboard:**
  - Usuário: `admin`
  - Senha: **[REMOVIDO]**
 - **Swagger API:**
  - Usuário: `api`
  - Senha: **[REMOVIDO]**

### n8n
- **URL:** https://n8n.example.com
 - **Usuário:** `admin`
 - **Senha:** **[REMOVIDO]**

## ⚠️ Importante

1. **Sempre use HTTPS** - os links HTTP redirecionam automaticamente
2. **Use os domínios**, não o IP direto (203.0.113.10)
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