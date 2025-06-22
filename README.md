# Automação n8n + WAHA + Chatwoot

Scripts para instalar e manter **Chatwoot**, **WAHA** e **n8n** em um servidor
Ubuntu utilizando Docker.  O projeto começou com o script `setup-wnc.sh` e foi
evoluindo para a ferramenta `wnc-cli.sh`, que centraliza todas as tarefas de
instalação, atualização e manutenção.

## Índice

1. [Pré‑requisitos](#pré-requisitos)
2. [Configuração inicial](#configuração-inicial)
3. [Scripts](#scripts)
4. [Instruções de uso](#instruções-de-uso)
5. [Fluxo de instalação recomendado](#fluxo-de-instalação-recomendado)
6. [Restauração do backup](#restauração-do-backup)
7. [Contribuindo](#contribuindo)

## Pré-requisitos

- Servidor Ubuntu 20.04 ou superior com acesso root
- Domínios DNS apontando para o servidor (`chat.saraivavision.com.br`, `waha.saraivavision.com.br` e `n8n.saraivavision.com.br`)
- Portas 80 e 443 liberadas no firewall
- Opcionalmente diretório de backup montado em `/mnt/backup`

## Configuração inicial

Edite o arquivo `setup-wnc.sh` caso deseje utilizar outros domínios ou e-mail
para os certificados.  No início do script há quatro variáveis principais:

```bash
CHAT_DOMAIN="chat.exemplo.com"
WAHA_DOMAIN="waha.exemplo.com"
N8N_DOMAIN="n8n.exemplo.com"
EMAIL_SSL="admin@exemplo.com"
```

Ajuste-as antes de executar a instalação para que os serviços sejam
configurados com seus próprios domínios.

## Scripts

| Arquivo | Função |
|---------|---------|

| `wnc-cli.sh` | Ferramenta de linha de comando para instalar e gerenciar a stack |
| `setup-wnc.sh` | Instala Chatwoot, WAHA e n8n via Docker, configura Nginx e SSL |
| `firewall-setup.sh` | Ativa UFW liberando 22/80/443 e bloqueando portas internas |
| `security_hardening.sh` | Configura `unattended-upgrades`, ajusta SSH e instala Fail2Ban |
| `fail2ban_setup.sh` | Instala e configura Fail2Ban (SSH e Nginx) |
| `backup-setup.sh` | Agenda backup diário de Postgres e Redis do Chatwoot, sessões WAHA e dados do n8n |
| `restore-backup.sh` | Restaura dados do backup em caso de falha |
| `maintenance_setup.sh` | Inicia Watchtower e cria `cron` semanal para `docker system prune` |
| `monitoring_setup.sh` | Instala `htop`, `node_exporter`, `cAdvisor`, Prometheus e Grafana |
| `check-services.sh` | Verifica portas abertas e testa as URLs públicas |
| `nodejs-codex-installer.sh` | Instala Node.js LTS e as CLIs do Codex e Codebuff |
| `manual_maintenance.sh` | Atualiza containers, renova SSL e checa dependências |
| `enable-http.sh` | Remove redirecionamentos HTTPS para liberar acesso HTTP |
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

### fail2ban_setup.sh
Instala e configura o Fail2Ban para monitorar acessos SSH e requisições Nginx:
```bash
sudo ./fail2ban_setup.sh
```

### backup-setup.sh
Realiza o dump do Postgres, arquiva o Redis do Chatwoot e copia os dados do WAHA e n8n para `/mnt/backup`, além de criar um cron diário:
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

## Restauração do backup

Caso precise restaurar os dados, utilize o script `restore-backup.sh`.  Por
padrão ele usa o backup mais recente presente em `/mnt/backup`:

```bash
sudo ./restore-backup.sh        # restaura o último backup
sudo ./restore-backup.sh 20240630  # restaura um backup específico
```

## Erro "secure cookie" no n8n

Se ao abrir o n8n surgir a mensagem:
"Your n8n server is configured to use a secure cookie, however you are either visiting this via an insecure URL, or using Safari",
verifique se o acesso está sendo feito por HTTPS. Caso esteja rodando localmente e sem Safari, utilize `http://localhost:5678`.
Se preferir desabilitar essa verificação (não recomendado), defina `N8N_SECURE_COOKIE=false` no arquivo `.env` do n8n.

## Contribuindo

Relate problemas ou envie melhorias abrindo issues e pull requests neste
repositório.  Sugestões são sempre bem‑vindas!

