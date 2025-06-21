# Automação n8n + WAHA + Chatwoot

Este repositório reúne scripts de instalação e manutenção para rodar **Chatwoot**, **WAHA** e **n8n** em um VPS Ubuntu utilizando Docker.
O script principal `setup-wnc.sh` monta toda a stack com Nginx e certificados SSL. Os demais arquivos tratam de firewall, segurança, backups e monitoramento.

## Pré-requisitos

- Servidor Ubuntu 20.04 ou superior com acesso root
- Domínios DNS apontando para o servidor (`chat.saraivavision.com.br`, `waha.saraivavision.com.br` e `n8n.saraivavision.com.br`)
- Portas 80 e 443 liberadas no firewall
- Opcionalmente diretório de backup montado em `/mnt/backup`

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
| `manual_maintenance.sh` | Atualiza containers, renova SSL e checa dependências |


## Instruções de uso

### setup-wnc.sh
Executa toda a instalação base. Rode como root:
```bash
sudo ./setup-wnc.sh
```
Ao final, Chatwoot, WAHA e n8n ficarão acessíveis via HTTPS nos domínios configurados.

### firewall-setup.sh
Habilita o UFW permitindo apenas as portas necessárias:
```bash
sudo ./firewall-setup.sh
```

### security_hardening.sh
Aplica configurações de hardening de sistema e instala Fail2Ban:
```bash
sudo ./security_hardening.sh
```

### backup-setup.sh
Realiza o dump do banco e copia arquivos para `/mnt/backup`, além de criar um cron diário:
```bash
sudo ./backup-setup.sh
```

### maintenance_setup.sh
Sobe o container Watchtower e agenda limpeza semanal do Docker:
```bash
sudo ./maintenance_setup.sh
```

### monitoring_setup.sh
Instala o node_exporter como serviço e executa o cAdvisor em container:
```bash
sudo ./monitoring_setup.sh
```

### check-services.sh
Mostra as portas em escuta e testa as URLs expostas:
```bash
sudo ./check-services.sh
```

### nodejs-codex-installer.sh
Instala a versão LTS do Node.js e as ferramentas @openai/codex e Codebuff:
```bash
sudo ./nodejs-codex-installer.sh
```

## Fluxo de instalação recomendado

1. Clone este repositório no servidor e dê permissão de execução aos scripts:
   ```bash
   git clone https://github.com/seu-usuario/n8n-waha-chatwoot.git
   cd n8n-waha-chatwoot
   chmod +x *.sh
   ```
2. (Opcional) Execute `firewall-setup.sh` e `security_hardening.sh` para preparar o sistema.
3. Rode `setup-wnc.sh` para instalar Chatwoot, WAHA e n8n.
4. Configure `backup-setup.sh`, `maintenance_setup.sh` e `monitoring_setup.sh` conforme necessidade.
5. Utilize `check-services.sh` para validar que tudo está funcionando.

Após a instalação, os serviços estarão disponíveis em:
- `https://chat.saraivavision.com.br`
- `https://waha.saraivavision.com.br`
- `https://n8n.saraivavision.com.br`

