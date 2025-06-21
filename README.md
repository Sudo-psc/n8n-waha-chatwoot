# Automação n8n + WAHA + Chatwoot

Este repositório contém scripts de instalação e manutenção para hospedar os seguintes serviços em um VPS Ubuntu:

* **Chatwoot** – plataforma de atendimento multicanal
* **WAHA** – API do WhatsApp em container Docker
* **n8n** – automações e integrações

O script principal `setup-wnc.sh` prepara toda a stack usando Docker, Nginx como proxy reverso e certificados SSL do Let's Encrypt. Os demais arquivos são utilitários opcionais para backup, segurança e monitoramento.

## Scripts

| Arquivo | Função |
|---------|---------|
| `setup-wnc.sh` | Instala Chatwoot, WAHA e n8n via Docker, configura Nginx e SSL |
| `firewall-setup.sh` | Ativa UFW liberando 22/80/443 e bloqueando portas internas |
| `security_hardening.sh` | Configura `unattended-upgrades`, ajusta SSH e instala Fail2Ban |
| `backup-setup.sh` | Agenda backup diário de Postgres, sessões WAHA e dados do n8n |
| `maintenance_setup.sh` | Inicia Watchtower e cria `cron` semanal para `docker system prune` |
| `monitoring_setup.sh` | Instala `node_exporter` e cAdvisor para coleta via Prometheus |
| `check-services.sh` | Verifica portas abertas e testa as URLs públicas |
| `nodejs-codex-installer.sh` | Instala Node.js LTS e as CLIs do Codex e Codebuff |

## Uso básico

1. Clone este repositório em seu servidor Ubuntu 20.04 ou superior.
2. Torne o script desejado executável: `chmod +x script.sh`.
3. Execute como `root` (ou com `sudo`) o script principal ou utilitário.

Exemplo para instalação completa:

```bash
sudo ./setup-wnc.sh
```

Após a conclusão, os serviços estarão acessíveis em:

- `https://chat.saraivavision.com.br`
- `https://waha.saraivavision.com.br`
- `https://n8n.saraivavision.com.br`

Consulte cada script para mais detalhes ou ajustes específicos.
