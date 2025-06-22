# Automação n8n + WAHA + Chatwoot (v2.0)

Scripts revisados e melhorados para instalar e manter **Chatwoot**, **WAHA** e **n8n** em servidores Ubuntu/Debian utilizando Docker. 

## 🚀 Novidades da Versão 2.0

- **Master Installer**: Script unificado com menu interativo
- **Validações Completas**: Verificação de pré-requisitos antes da instalação
- **Sistema de Rollback**: Desfaz alterações em caso de falha
- **Configurabilidade**: Todas as opções via variáveis de ambiente
- **Segurança Aprimorada**: Senhas fortes, firewall e hardening automático
- **Logs Estruturados**: Sistema de logging com cores e níveis

## Índice

1. [Instalação Rápida](#instalação-rápida)
2. [Pré-requisitos](#pré-requisitos)
3. [Scripts Disponíveis](#scripts-disponíveis)
4. [Configuração Avançada](#configuração-avançada)
5. [Comandos Úteis](#comandos-úteis)
6. [Solução de Problemas](#solução-de-problemas)
7. [Arquitetura](#arquitetura)

## Instalação Rápida

```bash
# Clone o repositório
git clone https://github.com/seu-usuario/n8n-waha-chatwoot.git
cd n8n-waha-chatwoot

# Torne os scripts executáveis
chmod +x *.sh

# Execute o instalador mestre
sudo ./master-installer.sh
```

O instalador mestre oferece um menu interativo para:
- Instalar todos os componentes de uma vez
- Instalar componentes individualmente
- Executar instalação na ordem recomendada
- Verificar status dos serviços

## Pré-requisitos

### Sistema
- Ubuntu 20.04+ ou Debian 10+ (64-bit)
- Mínimo 4GB RAM (8GB recomendado)
- Mínimo 20GB espaço em disco
- Acesso root (sudo)
- Conexão com internet

### Domínios e Rede
- 3 domínios/subdomínios configurados no DNS:
  - `chat.exemplo.com` → Chatwoot
  - `waha.exemplo.com` → WAHA  
  - `n8n.exemplo.com` → n8n
- Portas 80 e 443 liberadas
- IP público do servidor

## Scripts Disponíveis

### 🎯 Master Installer (`master-installer.sh`)
**NOVO!** Script principal com menu interativo para coordenar toda a instalação.

```bash
# Menu interativo
sudo ./master-installer.sh

# Instalação automática completa
sudo ./master-installer.sh --all

# Instalação recomendada (ordem otimizada)
sudo ./master-installer.sh --recommended

# Ver status
sudo ./master-installer.sh --status
```

### 🔒 Security Hardening (`security_hardening.sh`) v2.0
Fortalecimento completo de segurança do sistema.

**Melhorias v2.0:**
- Auditoria inicial de segurança
- Hardening modular (escolha o que aplicar)
- Kernel hardening via sysctl
- Auditd para auditoria de sistema
- AppArmor e detecção de rootkits
- Firewall com proteção anti-DDoS

### 🚀 Setup WNC (`setup-wnc.sh`) v2.0
Instalação principal do stack Chatwoot + WAHA + n8n.

**Melhorias v2.0:**
- Instalação interativa ou automática
- Verificação de DNS antes de instalar
- Healthchecks em todos os serviços
- Scripts auxiliares: `wnc-status`, `wnc-logs`, `wnc-restart`
- Credenciais salvas em `/root/.wnc_credentials`

### 📊 Monitoring Setup (`monitoring_setup.sh`) v2.0
Stack completo de monitoramento com Prometheus e Grafana.

**Melhorias v2.0:**
- Dashboards pré-configurados
- Alertas básicos incluídos
- Suporte opcional para Alertmanager
- Scripts: `monitoring-status`, `monitoring-backup`

### 🔧 Node.js Installer (`nodejs-codex-installer.sh`) v2.0
Instalação do Node.js e ferramentas de IA.

**Melhorias v2.0:**
- Cache de downloads
- Verificação de conectividade
- Atualização inteligente
- Script `node-info` para verificar ambiente

### 📦 Outros Scripts

| Script | Função | Status |
|--------|---------|--------|
| `wnc-cli.sh` | CLI para gerenciar a stack | Original |
| `backup-setup.sh` | Configura backups automáticos | Original |
| `restore-backup.sh` | Restaura backups | Original |
| `firewall-setup.sh` | Configura UFW básico | Original |
| `check-services.sh` | Verifica status dos serviços | Original |
| `update-images.sh` | Atualiza imagens Docker | Original |

## Configuração Avançada

### Variáveis de Ambiente

Todos os scripts v2.0 suportam configuração via variáveis:

```bash
# Exemplo: instalar apenas Chatwoot e n8n
sudo INSTALL_WAHA=0 ./setup-wnc.sh

# Instalar com domínios personalizados
sudo CHAT_DOMAIN=chat.meusite.com \
     WAHA_DOMAIN=api.meusite.com \
     N8N_DOMAIN=automacao.meusite.com \
     ./setup-wnc.sh

# Desabilitar rollback automático
sudo AUTO_ROLLBACK=0 ./setup-wnc.sh

# Modo debug
sudo DEBUG=1 ./setup-wnc.sh
```

### Portas Personalizadas

```bash
# Mudar portas dos serviços
sudo CHATWOOT_PORT=3100 \
     WAHA_PORT=3200 \
     N8N_PORT=3300 \
     ./setup-wnc.sh
```

## Comandos Úteis

### Status dos Serviços
```bash
# Ver status de todos os serviços WNC
wnc-status

# Ver logs de um serviço específico
wnc-logs chatwoot
wnc-logs waha
wnc-logs n8n

# Reiniciar serviços
wnc-restart all
wnc-restart chatwoot
```

### Monitoramento
```bash
# Status do monitoramento
monitoring-status

# Backup das configurações de monitoramento
monitoring-backup

# Acessar interfaces web
# Prometheus: http://servidor:9090
# Grafana: http://servidor:3000
# cAdvisor: http://servidor:8080
```

### Segurança
```bash
# Ver IPs bloqueados pelo Fail2Ban
sudo fail2ban-client status sshd

# Verificar logs de auditoria
sudo aureport --summary

# Status do AppArmor
sudo aa-status
```

## Solução de Problemas

### Erro de DNS
Se receber aviso sobre DNS não configurado:
1. Verifique se os domínios apontam para o IP do servidor
2. Aguarde propagação do DNS (até 48h)
3. Use `nslookup seu.dominio.com` para verificar

### Portas em Uso
Se alguma porta já estiver em uso:
1. Identifique o processo: `sudo ss -tlnp | grep :PORTA`
2. Pare o serviço conflitante ou use portas alternativas

### Containers não Iniciam
```bash
# Ver logs detalhados
docker compose -f /opt/chatwoot/docker-compose.yml logs
docker compose -f /opt/waha/docker-compose.yml logs
docker compose -f /opt/n8n/docker-compose.yml logs

# Reiniciar com logs
docker compose -f /opt/chatwoot/docker-compose.yml up
```

### Recuperar Credenciais
```bash
# Credenciais do WNC
sudo cat /root/.wnc_credentials

# Senha do Grafana
sudo cat /opt/monitoring/.env
```

## Arquitetura

### Estrutura de Diretórios
```
/opt/
├── chatwoot/          # Chatwoot + PostgreSQL + Redis
├── waha/              # WAHA WhatsApp API
├── n8n/               # n8n workflow automation
└── monitoring/        # Prometheus + Grafana

/var/log/
├── master-installer/  # Logs do instalador mestre
├── setup-wnc.log      # Log da instalação WNC
├── monitoring_setup.log # Log da instalação de monitoramento
└── security_hardening.log # Log do hardening

/root/
└── .wnc_credentials   # Credenciais dos serviços
```

### Portas Utilizadas

| Serviço | Porta Interna | Porta Externa |
|---------|---------------|---------------|
| Chatwoot | 3000 | 443 (HTTPS) |
| WAHA | 3001 | 443 (HTTPS) |
| n8n | 3002 | 443 (HTTPS) |
| PostgreSQL | 5432 | - |
| Redis | 6379 | - |
| Prometheus | 9090 | 9090 |
| Grafana | 3000 | 3000 |
| Node Exporter | 9100 | 9100 |
| cAdvisor | 8080 | 8080 |

### Rede Docker
Todos os serviços compartilham a rede `wcn_net` para comunicação interna.

## Segurança

### Medidas Implementadas
- ✅ Senhas fortes geradas automaticamente
- ✅ Firewall UFW com rate limiting
- ✅ Fail2Ban contra brute force
- ✅ Headers de segurança no Nginx
- ✅ SSH hardening
- ✅ Kernel hardening via sysctl
- ✅ Auditoria com auditd
- ✅ SSL/TLS com renovação automática

### Recomendações Adicionais
1. Configure chaves SSH ao invés de senhas
2. Restrinja acesso SSH por IP se possível
3. Faça backups regulares
4. Monitore logs regularmente
5. Mantenha o sistema atualizado

## Backup e Restauração

### Backup Automático
```bash
# Configurar backup diário
sudo ./backup-setup.sh

# Backup manual
sudo ./wnc-cli.sh backup
```

### Restaurar Backup
```bash
# Restaurar último backup
sudo ./restore-backup.sh

# Restaurar backup específico
sudo ./restore-backup.sh 20240630
```

## Contribuindo

Melhorias são bem-vindas! Por favor:

1. Fork o projeto
2. Crie uma branch para sua feature (`git checkout -b feature/AmazingFeature`)
3. Commit suas mudanças (`git commit -m 'Add some AmazingFeature'`)
4. Push para a branch (`git push origin feature/AmazingFeature`)
5. Abra um Pull Request

## Suporte

- **Issues**: Relate problemas no GitHub
- **Email**: philipe_cruz@outlook.com
- **Logs**: Verifique `/var/log/[nome-do-script].log`

---

**Versão**: 2.0.0  
**Última atualização**: 2024-12-20  
**Licença**: MIT

