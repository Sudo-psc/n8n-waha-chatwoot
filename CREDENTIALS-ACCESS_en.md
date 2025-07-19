# 🔐 Service Credentials

## 🌐 Access URLs

### Chatwoot
- **URL:** https://chat.example.com
- **Authentication:** Create your account on first access

### WAHA (WhatsApp HTTP API)
- **URL:** https://waha.example.com
  - **Dashboard:**
    - User: `admin`
    - Password: **[REMOVED]**
  - **Swagger API:**
    - User: `api`
    - Password: **[REMOVED]**

### n8n
- **URL:** https://n8n.example.com
  - **User:** `admin`
  - **Password:** **[REMOVED]**

## ⚠️ Important

1. **Always use HTTPS** - HTTP links are automatically redirected
2. **Use the domains**, not the raw IP (203.0.113.10)
3. If you see connection errors, clear your browser cache
4. For access issues, try an incognito/private window

## 🔄 Checking or changing credentials

Credentials are stored in:
- Chatwoot: managed by its own system
- WAHA: `/opt/waha/.env`
- n8n: `/opt/n8n/.env`

To edit, update the corresponding `.env` file and restart the container:
```bash
cd /opt/[service]
docker compose restart
```
