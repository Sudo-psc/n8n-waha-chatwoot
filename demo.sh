#!/usr/bin/env bash
# demo.sh - Demonstração das novas funcionalidades v2.0

# Cores
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

clear
echo -e "${BLUE}=== WNC Stack v2.0 - Demonstração ===${NC}"
echo
echo "Este script demonstra as principais funcionalidades da nova versão."
echo
read -p "Pressione ENTER para continuar..."

clear
echo -e "${YELLOW}1. Modo de Instalação Interativo${NC}"
echo
echo "O novo instalador oferece uma interface interativa que guia você"
echo "através de todo o processo de configuração:"
echo
echo "  - Seleção de componentes (todos, individual ou personalizado)"
echo "  - Configuração de domínios com valores padrão"
echo "  - Validação de DNS antes da instalação"
echo "  - Opções avançadas (skip DNS, skip SSL)"
echo
echo "Comando: ${GREEN}sudo ./setup-wnc.sh${NC}"
echo
read -p "Pressione ENTER para continuar..."

clear
echo -e "${YELLOW}2. Instalação Modular${NC}"
echo
echo "Agora você pode instalar apenas os componentes que precisa:"
echo
echo "Apenas Chatwoot:"
echo "${GREEN}sudo ./setup-wnc.sh --components=chatwoot --chat-domain=chat.example.com --email=admin@example.com${NC}"
echo
echo "Apenas WAHA:"
echo "${GREEN}sudo ./setup-wnc.sh --components=waha --waha-domain=waha.example.com --email=admin@example.com${NC}"
echo
echo "Apenas n8n:"
echo "${GREEN}sudo ./setup-wnc.sh --components=n8n --n8n-domain=n8n.example.com --email=admin@example.com${NC}"
echo
read -p "Pressione ENTER para continuar..."

clear
echo -e "${YELLOW}3. Gestão de Credenciais${NC}"
echo
echo "Todas as senhas geradas são salvas automaticamente em:"
echo "${BLUE}/root/.wnc-credentials${NC}"
echo
echo "Para visualizar as credenciais:"
echo "${GREEN}./wnc-cli.sh credentials${NC}"
echo
echo "Exemplo de saída:"
echo "CHATWOOT:"
echo "  url: https://chat.example.com"
echo "  postgres_password: abcd****efgh"
echo
echo "WAHA:"
echo "  url: https://waha.example.com"
echo "  dashboard_user: admin"
echo "  dashboard_password: 1234****5678"
echo
read -p "Pressione ENTER para continuar..."

clear
echo -e "${YELLOW}4. Monitoramento em Tempo Real${NC}"
echo
echo "Monitor integrado para acompanhar o status dos serviços:"
echo "${GREEN}./wnc-cli.sh monitor${NC}"
echo
echo "Mostra:"
echo "  - Status de cada serviço (OK/DOWN)"
echo "  - Uso de CPU e memória por container"
echo "  - Atualização automática a cada 2 segundos"
echo
read -p "Pressione ENTER para continuar..."

clear
echo -e "${YELLOW}5. Validação Completa da Instalação${NC}"
echo
echo "Script de teste que valida todos os aspectos da instalação:"
echo "${GREEN}sudo ./test-installation.sh${NC}"
echo
echo "Testa:"
echo "  ✓ Requisitos do sistema (RAM, disco, CPU)"
echo "  ✓ Docker e Docker Compose"
echo "  ✓ Nginx e configurações"
echo "  ✓ Certificados SSL e validade"
echo "  ✓ Conectividade entre serviços"
echo "  ✓ Configurações de backup"
echo "  ✓ Performance básica"
echo
read -p "Pressione ENTER para continuar..."

clear
echo -e "${YELLOW}6. Novos Comandos da CLI${NC}"
echo
echo "A CLI foi expandida com novos comandos úteis:"
echo
echo "${GREEN}./wnc-cli.sh restart chatwoot${NC}  # Reinicia um serviço"
echo "${GREEN}./wnc-cli.sh exec n8n bash${NC}     # Acessa shell do container"
echo "${GREEN}./wnc-cli.sh logs waha -f${NC}      # Logs em tempo real"
echo "${GREEN}./wnc-cli.sh status${NC}            # Status colorido e formatado"
echo
read -p "Pressione ENTER para continuar..."

clear
echo -e "${YELLOW}7. Sistema de Rollback${NC}"
echo
echo "Em caso de erro durante a instalação, o sistema automaticamente:"
echo
echo "  - Detecta a falha e registra no log"
echo "  - Executa rollback das alterações feitas"
echo "  - Restaura arquivos de backup"
echo "  - Remove containers/redes criados"
echo "  - Mantém o sistema no estado anterior"
echo
read -p "Pressione ENTER para continuar..."

clear
echo -e "${YELLOW}8. Modo Debug e Dry-Run${NC}"
echo
echo "Para diagnóstico e testes:"
echo
echo "Modo Debug (mostra detalhes de execução):"
echo "${GREEN}sudo ./setup-wnc.sh --debug${NC}"
echo
echo "Modo Dry-Run (simula sem fazer alterações):"
echo "${GREEN}sudo ./setup-wnc.sh --dry-run${NC}"
echo
echo "Combinar ambos:"
echo "${GREEN}sudo ./setup-wnc.sh --debug --dry-run${NC}"
echo
read -p "Pressione ENTER para continuar..."

clear
echo -e "${BLUE}=== Principais Melhorias da v2.0 ===${NC}"
echo
echo "✅ Interface interativa e amigável"
echo "✅ Validações robustas antes da instalação"
echo "✅ Gestão segura de credenciais"
echo "✅ Sistema de rollback automático"
echo "✅ Instalação modular de componentes"
echo "✅ Monitoramento e diagnóstico integrados"
echo "✅ Logs estruturados e coloridos"
echo "✅ Testes automatizados pós-instalação"
echo "✅ CLI expandida com novos comandos"
echo "✅ Documentação completa e exemplos"
echo
echo -e "${GREEN}Para começar, execute: sudo ./setup-wnc.sh${NC}"
echo
echo "Documentação completa em README.md e CHANGELOG.md"