# Guia de Atualização para v2.0

## 🚀 Atualizando da v1.0 para v2.0

Se você já tem a versão anterior instalada, siga este guia para atualizar.

### ⚠️ Importante

A v2.0 é totalmente compatível com instalações existentes. Suas configurações e dados serão preservados.

### 📋 Passos para Atualização

1. **Faça backup dos seus dados**
   ```bash
   sudo ./wnc-cli.sh backup
   ```

2. **Baixe a nova versão**
   ```bash
   cd /caminho/para/wnc-stack
   git pull origin main
   chmod +x *.sh
   ```

3. **Execute o teste de validação**
   ```bash
   sudo ./test-installation.sh
   ```

4. **Verifique suas credenciais**
   ```bash
   sudo ./wnc-cli.sh credentials
   ```

### 🆕 Novos Recursos Disponíveis

Após atualizar, você terá acesso a:

#### 1. **Novos comandos CLI**
```bash
# Reiniciar serviços individualmente
./wnc-cli.sh restart chatwoot

# Monitoramento em tempo real
./wnc-cli.sh monitor

# Executar comandos em containers
./wnc-cli.sh exec n8n bash

# Ver credenciais salvas
./wnc-cli.sh credentials
```

#### 2. **Script de validação**
```bash
# Testa toda a instalação
sudo ./test-installation.sh
```

#### 3. **Demonstração interativa**
```bash
# Veja todas as novas funcionalidades
./demo.sh
```

### 🔄 Migrando Configurações

Se você modificou os domínios no script anterior:

1. **Exporte suas configurações atuais**
   ```bash
   # Salve os domínios atuais
   grep "_DOMAIN=" setup-wnc.sh > domains.txt
   ```

2. **Use os mesmos domínios na nova instalação**
   ```bash
   sudo ./setup-wnc.sh \
     --chat-domain=SEU_DOMINIO_CHAT \
     --waha-domain=SEU_DOMINIO_WAHA \
     --n8n-domain=SEU_DOMINIO_N8N \
     --email=SEU_EMAIL
   ```

### 📝 Mudanças Importantes

1. **Credenciais agora são salvas automaticamente**
   - Local: `/root/.wnc-credentials`
   - Visualizar: `./wnc-cli.sh credentials`

2. **Logs melhorados**
   - Instalação: `/var/log/setup-wnc.log`
   - CLI: `/var/log/wnc-cli.log`
   - Testes: `/var/log/wnc-test.log`

3. **Novos arquivos de configuração**
   - Redis com senha e persistência melhorada
   - Health checks em todos os containers
   - Limites de recursos configurados

### 🆘 Suporte

Se encontrar problemas durante a atualização:

1. Verifique os logs:
   ```bash
   sudo tail -f /var/log/setup-wnc.log
   ```

2. Execute o teste de validação:
   ```bash
   sudo ./test-installation.sh
   ```

3. Restaure o backup se necessário:
   ```bash
   sudo ./wnc-cli.sh restore latest
   ```

### ✅ Checklist Pós-Atualização

- [ ] Backup realizado com sucesso
- [ ] Scripts atualizados e com permissão de execução
- [ ] Teste de validação passou sem erros críticos
- [ ] Serviços estão respondendo normalmente
- [ ] Credenciais foram preservadas
- [ ] Certificados SSL continuam válidos

### 🎉 Aproveite a v2.0!

Explore as novas funcionalidades executando:
```bash
./demo.sh
```

Para ajuda completa:
```bash
./wnc-cli.sh --help
```