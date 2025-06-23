# CHANGELOG - Script de Instalação WNC v2.0

## Versão 2.0 - Melhorias Implementadas

### 🎨 Interface e Usabilidade
- **Modo Interativo**: Interface amigável com seleção de componentes e configuração guiada
- **Cores no Output**: Mensagens coloridas para melhor visualização (INFO, WARN, ERROR, SUCCESS)
- **Barra de Progresso**: Indicador visual do progresso da instalação
- **Banner Inicial**: Logo ASCII art para melhor apresentação

### 🔐 Segurança
- **Gestão de Credenciais**: Todas as senhas são salvas em arquivo seguro (`/root/.wnc-credentials`)
- **Senhas Fortes**: Geração automática de senhas complexas com OpenSSL
- **Permissões Adequadas**: Arquivo de credenciais com permissão 600 (apenas root)
- **Headers de Segurança**: Configuração completa de headers HTTP no Nginx
- **Rate Limiting**: Proteção contra abuso com limites de requisições

### ✅ Validações e Verificações
- **Checagem de Pré-requisitos**: 
  - Verificação de sistema operacional
  - Espaço em disco mínimo (10GB)
  - Memória RAM recomendada (2GB)
  - Conectividade com internet
- **Validação de DNS**: Verifica se domínios resolvem antes de instalar
- **Verificação de Portas**: Alerta sobre portas já em uso
- **Testes Automatizados**: Valida funcionamento após instalação

### 🔄 Tratamento de Erros
- **Sistema de Rollback**: Desfaz alterações em caso de erro
- **Trap de Erros**: Captura e trata erros com informações detalhadas
- **Logs Estruturados**: Todos os eventos são registrados em `/var/log/setup-wnc.log`
- **Modo Debug**: Flag `--debug` para diagnóstico detalhado

### 🚀 Funcionalidades Avançadas
- **Instalação Modular**: Permite instalar componentes individualmente
- **Modo Dry-Run**: Simula instalação sem fazer alterações
- **Argumentos CLI**: Suporte completo para automação
- **Health Checks**: Configuração de verificações de saúde nos containers
- **Resource Limits**: Limites de memória configurados nos containers

### 📦 Melhorias no Docker
- **Versões Atualizadas**: 
  - PostgreSQL 15 com pgvector
  - Redis 7 Alpine
  - Imagens mais recentes de todos os serviços
- **Dependências com Condições**: Containers aguardam serviços ficarem saudáveis
- **Volumes Nomeados**: Melhor organização dos dados persistentes
- **Networks Externas**: Isolamento adequado da rede

### 🔧 Configurações Aprimoradas
- **Nginx Otimizado**:
  - Compressão habilitada
  - Timeouts configurados
  - Buffer sizes ajustados
  - SSL/TLS moderno (TLS 1.2+)
- **Redis com Persistência**: Configuração completa de AOF e snapshots
- **Logs Centralizados**: Todos os serviços com logs estruturados

### 📝 Scripts Adicionais
- **Monitor de Status**: Script `wnc-monitor` para verificar saúde dos serviços
- **Renovação SSL Automática**: Timer systemd para renovação de certificados
- **Backup Melhorado**: Scripts de backup com rotação automática

### 🎯 Opções de Linha de Comando
```bash
--debug              # Ativa modo debug
--dry-run           # Simula instalação
--skip-dns          # Pula verificação DNS
--skip-ssl          # Pula geração de certificados
--chat-domain=      # Define domínio do Chatwoot
--waha-domain=      # Define domínio do WAHA
--n8n-domain=       # Define domínio do n8n
--email=            # Define email para SSL
--components=       # Lista de componentes (chatwoot,waha,n8n)
```

### 🔍 Exemplos de Uso

1. **Instalação Interativa** (Recomendado para primeira vez):
   ```bash
   sudo ./setup-wnc.sh
   ```

2. **Instalação Automatizada Completa**:
   ```bash
   sudo ./setup-wnc.sh \
     --chat-domain=chat.example.com \
     --waha-domain=waha.example.com \
     --n8n-domain=n8n.example.com \
     --email=admin@example.com
   ```

3. **Instalar Apenas Chatwoot**:
   ```bash
   sudo ./setup-wnc.sh \
     --components=chatwoot \
     --chat-domain=chat.example.com \
     --email=admin@example.com
   ```

4. **Modo Debug com Dry-Run**:
   ```bash
   sudo ./setup-wnc.sh --debug --dry-run
   ```

### 📊 Comparação de Versões

| Recurso | v1.0 | v2.0 |
|---------|------|------|
| Configuração Interativa | ❌ | ✅ |
| Salvamento de Credenciais | ❌ | ✅ |
| Validação de DNS | ❌ | ✅ |
| Sistema de Rollback | ❌ | ✅ |
| Instalação Modular | ❌ | ✅ |
| Modo Debug | ❌ | ✅ |
| Testes Automatizados | ❌ | ✅ |
| Health Checks | ❌ | ✅ |
| Rate Limiting | ❌ | ✅ |
| Logs Estruturados | Básico | Completo |

### 🛡️ Segurança Adicional

1. **Firewall**: Considere executar `./firewall-setup.sh` após a instalação
2. **Fail2ban**: Execute `./fail2ban_setup.sh` para proteção contra força bruta
3. **Hardening**: Use `./security_hardening.sh` para fortalecer o sistema
4. **Monitoring**: Configure `./monitoring_setup.sh` para monitoramento completo

### 📚 Próximos Passos Após Instalação

1. **Verificar Credenciais**:
   ```bash
   sudo cat /root/.wnc-credentials
   ```

2. **Monitorar Serviços**:
   ```bash
   sudo wnc-monitor
   ```

3. **Ver Logs**:
   ```bash
   ./wnc-cli.sh logs chatwoot
   ./wnc-cli.sh logs waha
   ./wnc-cli.sh logs n8n
   ```

4. **Fazer Backup**:
   ```bash
   ./wnc-cli.sh backup
   ```

### 🐛 Correções de Bugs
- Corrigido problema com criação de rede Docker
- Melhor tratamento de erros em verificações DNS
- Timeout adequado para aguardar serviços iniciarem
- Correção na detecção de portas em uso