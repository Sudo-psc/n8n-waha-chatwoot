# Automação n8n + WAHA + Chatwoot

Este repositório reúne scripts de instalação e manutenção para rodar **Chatwoot**, **WAHA** e **n8n** em um VPS Ubuntu utilizando Docker.
Antigamente a instalação era feita diretamente com `setup-wnc.sh`, mas a partir desta versão há também a ferramenta `wnc-cli.sh` que centraliza as tarefas de instalação, atualização e manutenção.

## Pré-requisitos

- Servidor Ubuntu 20.04 ou superior com acesso root
- Domínios DNS apontando para o servidor (`chat.saraivavision.com.br`, `waha.saraivavision.com.br` e `n8n.saraivavision.com.br`)
- Portas 80 e 443 liberadas no firewall
- Opcionalmente diretório de backup montado em `/mnt/backup`

## Scripts

| Arquivo | Função |
|---------|---------|

| `wnc-cli.sh` | Ferramenta de linha de comando para instalar e gerenciar a stack |
| `setup-wnc.sh` | Instala Chatwoot, WAHA e n8n via Docker, configura Nginx e SSL |
| `firewall-setup.sh` | Ativa UFW liberando 22/80/443 e bloqueando portas internas |
| `security_hardening.sh` | Configura `unattended-upgrades`, ajusta SSH e instala Fail2Ban |
| `backup-setup.sh` | Agenda backup diário de Postgres, sessões WAHA e dados do n8n |
| `restore-backup.sh` | Restaura dados do backup em caso de falha |
| `maintenance_setup.sh` | Inicia Watchtower e cria `cron` semanal para `docker system prune` |
| `monitoring_setup.sh` | Instala `htop`, `node_exporter`, `cAdvisor`, Prometheus e Grafana |
| `check-services.sh` | Verifica portas abertas e testa as URLs públicas |
| `nodejs-codex-installer.sh` | Instala Node.js LTS e as CLIs do Codex e Codebuff |
| `manual_maintenance.sh` | Atualiza containers, renova SSL e checa dependências |
| `update-images.sh` | Atualiza as imagens Docker para versões específicas |


## Instruções de uso

### wnc-cli.sh
Ferramenta principal para instalar e gerenciar a stack. Exemplos:
```bash
sudo ./wnc-cli.sh install          # instala tudo
sudo ./wnc-cli.sh update           # atualiza containers
sudo ./wnc-cli.sh backup           # executa backup manual
sudo ./wnc-cli.sh logs n8n         # mostra logs do serviço
```

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
Instala o `htop` para monitoramento rápido e sobe o stack Prometheus + Grafana \
além dos exporters node_exporter e cAdvisor:
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

### update-images.sh
Atualiza as imagens Docker para as versões mais recentes ou uma tag específica:
```bash
sudo ./update-images.sh [chatwoot|waha|n8n|all] [tag]
```

## Fluxo de instalação recomendado

1. Clone este repositório no servidor e dê permissão de execução aos scripts:
   ```bash
   git clone https://github.com/seu-usuario/n8n-waha-chatwoot.git
   cd n8n-waha-chatwoot
   chmod +x *.sh
   ```
2. (Opcional) Execute `firewall-setup.sh` e `security_hardening.sh` para preparar o sistema.
3. Utilize `wnc-cli.sh install` para instalar Chatwoot, WAHA e n8n.
4. Execute `wnc-cli.sh update` e `wnc-cli.sh backup` sempre que necessário ou agende via cron.
5. Utilize `check-services.sh` para validar que tudo está funcionando.

Após a instalação, os serviços estarão disponíveis em:
- `https://chat.saraivavision.com.br`
- `https://waha.saraivavision.com.br`
- `https://n8n.saraivavision.com.br`

