# Changelog do Instalador - setup-wnc.sh

## Versão 2.0 - Junho 2025

### 🔧 Correções Implementadas

#### 1. **Configuração de Nginx Melhorada**
- **Problema**: CSP muito restritiva causava tela branca no Chatwoot e WAHA
- **Solução**: Política CSP otimizada para aplicações JavaScript modernas
- **Antes**: `Content-Security-Policy "default-src 'self';"`
- **Depois**: `Content-Security-Policy "default-src 'self' 'unsafe-inline' 'unsafe-eval'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:;"`

#### 2. **Redirecionamento HTTP → HTTPS**
- **Problema**: Configurações iniciais não tinham redirecionamento automático
- **Solução**: Adicionado redirecionamento 301 automático para HTTPS
- **Implementação**: `return 301 https://$server_name$request_uri;`

#### 3. **Estrutura de Certificados SSL**
- **Problema**: Ordem de criação causava conflitos
- **Solução**: Processo em duas etapas:
  1. Configuração básica HTTP para obter certificados
  2. Configuração completa HTTPS após emissão dos certificados

#### 4. **Scripts de Teste Automáticos**
- **Adicionado**: Scripts de teste para cada serviço
- **Localização**: `/root/test-*.sh`
- **Funcionalidades**:
  - Teste de conectividade HTTP/HTTPS
  - Verificação de recursos estáticos
  - Validação de APIs
  - Status dos containers Docker

### 📋 Novos Recursos

#### Scripts Utilitários Criados Automaticamente:
1. **`/root/check-services.sh`** - Verificação geral de todos os serviços
2. **`/root/test-chatwoot.sh`** - Teste específico do Chatwoot
3. **`/root/test-waha-dashboard.sh`** - Teste específico do WAHA

#### Melhorias na Experiência do Usuário:
- **Logging melhorado**: Mensagens mais descritivas durante a instalação
- **Conclusão detalhada**: Resumo completo das URLs e próximos passos
- **Documentação automática**: Scripts de teste prontos para uso

### 🔒 Segurança Aprimorada

#### Cabeçalhos de Segurança:
- **HSTS**: `Strict-Transport-Security: max-age=31536000`
- **X-Frame-Options**: `SAMEORIGIN`
- **X-Content-Type-Options**: `nosniff`
- **CSP**: Política otimizada para funcionalidade sem comprometer segurança

#### Certificados SSL:
- **Renovação automática**: Cron job configurado automaticamente
- **Deploy hooks**: Reload do nginx após renovação
- **Validação**: Verificação de sintaxe antes de aplicar mudanças

### 🧪 Testes e Validação

#### Testes Automáticos Incluídos:
- ✅ Conectividade HTTP/HTTPS para todos os serviços
- ✅ Validação de redirecionamentos
- ✅ Verificação de recursos estáticos (CSS, JS)
- ✅ Teste de APIs sem autenticação
- ✅ Status dos containers Docker
- ✅ Validação de cabeçalhos de segurança

### 📝 Compatibilidade

#### Versões Testadas:
- **Ubuntu**: 20.04 LTS, 22.04 LTS
- **Docker**: 24.0+
- **Nginx**: 1.18+
- **Certbot**: 1.0+

#### Domínios Suportados:
- `chat.example.com` → Chatwoot
- `waha.example.com` → WAHA  
- `n8n.example.com` → n8n

### 🚀 Instruções de Uso

```bash
# Download e execução
wget https://seu-repositorio.com/setup-wnc.sh
chmod +x setup-wnc.sh
sudo ./setup-wnc.sh

# Verificação pós-instalação
sudo /root/check-services.sh
```

### 📞 Suporte

**Autor**: philipe_cruz@outlook.com
**Versão**: 2.0
**Data**: Junho 2025 