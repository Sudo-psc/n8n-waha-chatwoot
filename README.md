# WNC Stack - Chatwoot + WAHA + n8n

## 🚀 Versão 2.0 - Instalador Melhorado

Sistema completo de automação com WhatsApp, CRM e workflows automatizados.

### 📋 Componentes

- **[Chatwoot](https://www.chatwoot.com/)** - CRM e plataforma de atendimento multicanal
- **[WAHA](https://waha.devlike.pro/)** - API HTTP para WhatsApp
- **[n8n](https://n8n.io/)** - Plataforma de automação de workflows

### ✨ Novidades da v2.0

- 🎨 **Interface Interativa** - Configuração guiada passo a passo
- 🔐 **Gestão de Credenciais** - Senhas salvas com segurança
- ✅ **Validações Robustas** - Verifica DNS, portas e recursos
- 🔄 **Sistema de Rollback** - Recuperação automática em caso de erro
- 🚀 **Instalação Modular** - Instale apenas o que precisa
- 📊 **Monitoramento** - Ferramentas para acompanhar a saúde dos serviços

## 📦 Pré-requisitos

- **Sistema Operacional:** Ubuntu 20.04+ ou Debian 10+
- **Memória RAM:** Mínimo 2GB (recomendado 4GB+)
- **Espaço em Disco:** Mínimo 10GB livres
- **CPU:** Mínimo 2 cores
- **Domínios:** 3 domínios apontando para o servidor
- **Acesso:** Root ou sudo

## 🛠️ Instalação Rápida

### 1. Clone o repositório

```bash
git clone https://github.com/seu-usuario/wnc-stack.git
cd wnc-stack
chmod +x *.sh
```

### 2. Execute o instalador

#### Modo Interativo (Recomendado)
```bash
sudo ./setup-wnc.sh
```

#### Modo Automático
```bash
sudo ./setup-wnc.sh \
  --chat-domain=chat.example.com \
  --waha-domain=waha.example.com \
  --n8n-domain=n8n.example.com \
  --email=admin@example.com
```

### 3. Valide a instalação
```bash
sudo ./test-installation.sh
```

## 🎯 Opções de Instalação

### Instalação Completa
```bash
sudo ./setup-wnc.sh
# Selecione opção 1 no menu
```

### Apenas Chatwoot
```bash
sudo ./setup-wnc.sh --components=chatwoot \
  --chat-domain=chat.example.com \
  --email=admin@example.com
```

### Apenas WAHA
```bash
sudo ./setup-wnc.sh --components=waha \
  --waha-domain=waha.example.com \
  --email=admin@example.com
```

### Apenas n8n
```bash
sudo ./setup-wnc.sh --components=n8n \
  --n8n-domain=n8n.example.com \
  --email=admin@example.com
```

## 🔧 Gerenciamento com WNC-CLI

### Comandos Principais

```bash
# Ver status de todos os serviços
./wnc-cli.sh status

# Ver credenciais salvas
./wnc-cli.sh credentials

# Monitorar recursos em tempo real
./wnc-cli.sh monitor

# Ver logs de um serviço
./wnc-cli.sh logs chatwoot
./wnc-cli.sh logs waha
./wnc-cli.sh logs n8n

# Reiniciar um serviço
./wnc-cli.sh restart chatwoot

# Fazer backup
./wnc-cli.sh backup

# Executar comando em container
./wnc-cli.sh exec n8n bash
```

## 💻 Gerenciador de Scripts

Utilitário para descobrir e executar scripts do repositório.

```bash
cd cli-script-manager
./main.sh --list
```

Modo interativo:
```bash
./main.sh --interactive
```

Gerar documentação:
```bash
./main.sh --update-docs
```

## 🔐 Credenciais e Acessos

Após a instalação, as credenciais são salvas em `/root/.wnc-credentials`.

Para visualizar:
```bash
sudo ./wnc-cli.sh credentials
```

### Acessar Chatwoot

1. Acesse: `https://chat.seu-dominio.com`
2. Crie o primeiro usuário admin:
```bash
sudo docker compose -f /opt/chatwoot/docker-compose.yml run --rm rails bundle exec rails c
```
No console Rails:
```ruby
User.create!(name: 'Admin', email: 'admin@example.com', password: 'senha123', confirmed_at: Time.now)
```

### Acessar WAHA

1. Acesse: `https://waha.seu-dominio.com`
2. Use as credenciais mostradas pelo comando `credentials`
3. Conecte seu WhatsApp escaneando o QR Code

### Acessar n8n

1. Acesse: `https://n8n.seu-dominio.com`
2. Use as credenciais mostradas pelo comando `credentials`
3. Crie seus workflows de automação

## 📊 Monitoramento e Manutenção

### Verificar Saúde dos Serviços
```bash
# Status completo
./wnc-cli.sh status

# Monitoramento em tempo real
./wnc-cli.sh monitor

# Teste completo da instalação
sudo ./test-installation.sh
```

### Atualizar Serviços
```bash
# Atualiza todos os containers e renova certificados
./wnc-cli.sh update
```

### Backup e Restauração

#### Backup Manual
```bash
./wnc-cli.sh backup
```

#### Backup Automático
O sistema configura backup diário às 3:00 AM automaticamente.

#### Restaurar Backup
```bash
# Restaurar último backup
./wnc-cli.sh restore latest

# Restaurar backup específico
./wnc-cli.sh restore 2024-01-15
```

## 🛡️ Segurança Adicional

### 1. Configurar Firewall
```bash
sudo ./firewall-setup.sh
```

### 2. Instalar Fail2ban
```bash
sudo ./fail2ban_setup.sh
```

### 3. Hardening do Sistema
```bash
sudo ./security_hardening.sh
```

### 4. Configurar Monitoramento
```bash
sudo ./monitoring_setup.sh
```

## 🐛 Solução de Problemas

### Logs Detalhados

```bash
# Logs da instalação
sudo cat /var/log/setup-wnc.log

# Logs de um serviço específico
./wnc-cli.sh logs chatwoot --tail=100

# Logs do Nginx
sudo tail -f /var/log/nginx/error.log
```

### Problemas Comuns

#### 1. Erro de DNS
- Verifique se os domínios apontam para o IP correto
- Use `--skip-dns` para pular verificação durante testes

#### 2. Porta em Uso
- Verifique portas com: `sudo ss -tuln | grep -E ':(80|443|3000|3001|3002)'`
- Pare serviços conflitantes antes da instalação

#### 3. Certificado SSL Falhando
- Verifique se a porta 80 está acessível externamente
- Use `--skip-ssl` para instalação sem HTTPS (não recomendado para produção)

## 📚 Scripts Incluídos

| Script | Descrição |
|--------|-----------|
| `setup-wnc.sh` | Instalador principal (v2.0) |
| `wnc-cli.sh` | CLI para gerenciamento |
| `test-installation.sh` | Validação completa da instalação |
| `backup-setup.sh` | Configuração de backups |
| `restore-backup.sh` | Restauração de backups |
| `manual_maintenance.sh` | Manutenção e atualizações |
| `firewall-setup.sh` | Configuração de firewall |
| `fail2ban_setup.sh` | Proteção contra força bruta |
| `security_hardening.sh` | Hardening de segurança |
| `monitoring_setup.sh` | Setup de monitoramento |
| `cli-script-manager/main.sh` | Gerenciador de scripts |

## 🤝 Contribuindo

Contribuições são bem-vindas! Por favor:

1. Fork o projeto
2. Crie sua feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit suas mudanças (`git commit -m 'Add some AmazingFeature'`)
4. Push para a branch (`git push origin feature/AmazingFeature`)
5. Abra um Pull Request

## 📝 Changelog

Veja [CHANGELOG.md](CHANGELOG.md) para lista detalhada de mudanças.

## 📄 Licença

Este projeto está sob a licença MIT. Veja o arquivo [LICENSE](LICENSE) para mais detalhes.

## 👥 Autores

- **Philipe Cruz** - *Desenvolvimento inicial* - [philipe_cruz@outlook.com](mailto:philipe_cruz@outlook.com)

## 🙏 Agradecimentos

- Equipe Chatwoot pela excelente plataforma
- Desenvolvedores do WAHA pela API WhatsApp
- Comunidade n8n pelos workflows incríveis

---

**Nota:** Este é um projeto em constante evolução. Sugestões e melhorias são sempre bem-vindas!

