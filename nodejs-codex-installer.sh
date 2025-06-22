#!/usr/bin/env bash
###############################################################################
# Script: nodejs-codex-installer.sh
# Descrição: Instala Node.js LTS (20.x), @openai/codex CLI e Codebuff CLI
# Sistema-alvo: Ubuntu/Debian (testado em Ubuntu 20.04, 22.04, 24.04)
# Versão: 2.0.0
# Autor: philipe_cruz@outlook.com
#
# Melhorias v2.0:
# - Validações de sistema e pré-requisitos
# - Configuração via variáveis de ambiente
# - Sistema de rollback em caso de falha
# - Cache de downloads para reinstalação
# - Verificação de conectividade
# - Limpeza automática pós-instalação
###############################################################################

# Configuração de cores para output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Structured logging ----------------------------------------------------------
SCRIPT_NAME=$(basename "$0" .sh)
LOG_FILE="/var/log/${SCRIPT_NAME}.log"
CACHE_DIR="/var/cache/${SCRIPT_NAME}"
BACKUP_DIR="/var/backups/${SCRIPT_NAME}"

mkdir -p "$(dirname "$LOG_FILE")" "$CACHE_DIR" "$BACKUP_DIR"
touch "$LOG_FILE"

log() { 
    local level="$1"
    shift
    echo "$(date '+%F %T') [$level] $*" | tee -a "$LOG_FILE"
}

info()  { echo -e "${GREEN}[INFO]${NC} $*" | tee -a "$LOG_FILE"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; }
debug() { [[ "${DEBUG:-0}" == "1" ]] && echo -e "${BLUE}[DEBUG]${NC} $*" | tee -a "$LOG_FILE"; }

# Configuração de tratamento de erros
set -Eeuo pipefail
trap 'handle_error $? $LINENO "$BASH_COMMAND"' ERR

# Lista de recursos criados para rollback
declare -a CREATED_RESOURCES=()
declare -a INSTALLED_PACKAGES=()

handle_error() {
    local exit_code=$1
    local line_number=$2
    local command=$3
    
    error "Erro na linha $line_number: comando '$command' falhou com código $exit_code"
    
    if [[ "${AUTO_ROLLBACK:-1}" == "1" ]]; then
        warn "Iniciando rollback automático..."
        rollback
    fi
    
    exit $exit_code
}

# Função de rollback
rollback() {
    info "Executando rollback dos recursos criados..."
    
    # Remover pacotes npm globais instalados
    for package in "${INSTALLED_PACKAGES[@]}"; do
        info "Removendo pacote npm: $package"
        npm uninstall -g "$package" 2>/dev/null || true
    done
    
    # Remover arquivos criados
    for resource in "${CREATED_RESOURCES[@]}"; do
        case "$resource" in
            "file:*")
                local file="${resource#file:}"
                [[ -f "$file" ]] && rm -f "$file"
                ;;
            "dir:*")
                local dir="${resource#dir:}"
                [[ -d "$dir" ]] && rm -rf "$dir"
                ;;
        esac
    done
    
    info "Rollback concluído"
}

# Configurações padrão (podem ser sobrescritas por variáveis de ambiente)
: "${NODE_VERSION:=20}"
: "${INSTALL_CODEX:=1}"
: "${INSTALL_CODEBUFF:=1}"
: "${UPDATE_EXISTING:=1}"
: "${CLEAN_CACHE:=1}"
: "${MIN_MEMORY_MB:=512}"
: "${MIN_DISK_MB:=500}"

#-----------------------------------------------------------------------------
# Funções utilitárias
#-----------------------------------------------------------------------------
cmd_exists() { 
    command -v "$1" &>/dev/null 
}

check_connectivity() {
    local test_urls=(
        "https://deb.nodesource.com"
        "https://registry.npmjs.org"
        "https://github.com"
    )
    
    info "Verificando conectividade..."
    
    for url in "${test_urls[@]}"; do
        if ! curl -s --head --fail "$url" >/dev/null 2>&1; then
            error "Não foi possível acessar: $url"
            error "Verifique sua conexão com a internet"
            return 1
        fi
        debug "Conectividade OK: $url"
    done
    
    return 0
}

backup_file() {
    local file=$1
    if [[ -f "$file" ]]; then
        local backup="${BACKUP_DIR}/$(basename "$file").$(date +%s)"
        cp "$file" "$backup"
        debug "Backup criado: $backup"
        CREATED_RESOURCES+=("file:$backup")
    fi
}

#-----------------------------------------------------------------------------
# Validações de sistema
#-----------------------------------------------------------------------------
check_system_requirements() {
    info "Verificando requisitos do sistema..."
    
    # Verificar se é root
    if [[ $EUID -ne 0 ]]; then
        error "Este script deve ser executado como root (use sudo)"
        exit 1
    fi
    
    # Verificar OS
    if [[ ! -f /etc/os-release ]]; then
        error "Arquivo /etc/os-release não encontrado"
        exit 1
    fi
    
    source /etc/os-release
    if ! [[ "$ID" =~ ^(ubuntu|debian)$ ]]; then
        warn "Sistema operacional: $ID $VERSION_ID"
        warn "Este script foi testado apenas em Ubuntu/Debian"
        read -p "Deseja continuar mesmo assim? [s/N]: " -r
        if [[ ! "$REPLY" =~ ^[Ss]$ ]]; then
            info "Instalação cancelada pelo usuário"
            exit 0
        fi
    fi
    
    # Verificar arquitetura
    local arch=$(uname -m)
    if ! [[ "$arch" =~ ^(x86_64|aarch64|arm64)$ ]]; then
        error "Arquitetura não suportada: $arch"
        error "Apenas x86_64 e arm64 são suportados"
        exit 1
    fi
    
    # Verificar memória
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    if [[ $total_mem -lt $MIN_MEMORY_MB ]]; then
        error "Memória insuficiente: ${total_mem}MB disponível, ${MIN_MEMORY_MB}MB necessário"
        exit 1
    fi
    
    # Verificar espaço em disco
    local available_disk=$(df -BM / | awk 'NR==2 {print $4}' | sed 's/M//')
    if [[ $available_disk -lt $MIN_DISK_MB ]]; then
        error "Espaço em disco insuficiente: ${available_disk}MB disponível, ${MIN_DISK_MB}MB necessário"
        exit 1
    fi
    
    info "Sistema operacional: $PRETTY_NAME"
    info "Arquitetura: $arch"
    info "Memória: ${total_mem}MB"
    info "Espaço em disco: ${available_disk}MB"
    info "Todos os requisitos foram atendidos ✓"
}

#-----------------------------------------------------------------------------
# Instalação de dependências base
#-----------------------------------------------------------------------------
install_dependencies() {
    info "Instalando dependências base..."
    
    # Atualizar índice de pacotes
    apt-get update -qq
    
    # Instalar dependências essenciais
    local deps=(
        curl
        ca-certificates
        gnupg
        lsb-release
        software-properties-common
        build-essential
        git
    )
    
    for dep in "${deps[@]}"; do
        if ! dpkg -l | grep -q "^ii  $dep"; then
            debug "Instalando: $dep"
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$dep" >/dev/null 2>&1
        fi
    done
    
    info "Dependências base instaladas ✓"
}

#-----------------------------------------------------------------------------
# Instalação/Atualização do Node.js
#-----------------------------------------------------------------------------
install_node() {
    info "Verificando instalação do Node.js..."
    
    local need_install=0
    local current_version=""
    
    if cmd_exists node; then
        current_version=$(node -v | sed 's/^v//')
        local current_major=${current_version%%.*}
        
        info "Node.js $current_version encontrado"
        
        if (( current_major >= NODE_VERSION )); then
            if [[ "$UPDATE_EXISTING" == "1" ]]; then
                info "Verificando atualizações para Node.js ${NODE_VERSION}.x..."
                need_install=1
            else
                info "Node.js $current_version já atende aos requisitos ✓"
                return
            fi
        else
            warn "Node.js $current_version está desatualizado"
            warn "Será atualizado para ${NODE_VERSION}.x"
            need_install=1
        fi
    else
        info "Node.js não encontrado, será instalado"
        need_install=1
    fi
    
    if [[ $need_install -eq 1 ]]; then
        # Remover instalações antigas se existirem
        if [[ -f /etc/apt/sources.list.d/nodesource.list ]]; then
            backup_file "/etc/apt/sources.list.d/nodesource.list"
            rm -f /etc/apt/sources.list.d/nodesource.list
        fi
        
        # Instalar via NodeSource
        info "Configurando repositório NodeSource para Node.js ${NODE_VERSION}.x..."
        
        local setup_script="${CACHE_DIR}/nodesource_setup_${NODE_VERSION}.sh"
        
        # Baixar script de setup se não estiver em cache
        if [[ ! -f "$setup_script" ]] || [[ $(find "$setup_script" -mtime +7 -print) ]]; then
            debug "Baixando script de setup do NodeSource..."
            curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" -o "$setup_script"
            chmod +x "$setup_script"
        else
            debug "Usando script de setup em cache"
        fi
        
        # Executar script de setup
        bash "$setup_script"
        
        # Instalar Node.js
        info "Instalando Node.js ${NODE_VERSION}.x..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs
        
        # Verificar instalação
        if cmd_exists node; then
            info "Node.js $(node -v) instalado com sucesso ✓"
        else
            error "Falha na instalação do Node.js"
            exit 1
        fi
    fi
    
    # Atualizar npm para última versão
    info "Atualizando npm para última versão..."
    npm install -g npm@latest >/dev/null 2>&1
    info "npm $(npm -v) ✓"
}

#-----------------------------------------------------------------------------
# Instalação das ferramentas CLI
#-----------------------------------------------------------------------------
install_cli_tools() {
    info "Instalando ferramentas CLI..."
    
    # Configurar npm para melhor performance
    npm config set progress false
    npm config set loglevel error
    
    # @openai/codex CLI
    if [[ "$INSTALL_CODEX" == "1" ]]; then
        info "Verificando @openai/codex CLI..."
        
        if npm list -g --depth=0 2>/dev/null | grep -q '@openai/codex'; then
            if [[ "$UPDATE_EXISTING" == "1" ]]; then
                info "Atualizando @openai/codex CLI..."
                npm update -g @openai/codex >/dev/null 2>&1
            else
                info "@openai/codex já instalado ✓"
            fi
        else
            info "Instalando @openai/codex CLI..."
            if npm install -g @openai/codex >/dev/null 2>&1; then
                INSTALLED_PACKAGES+=("@openai/codex")
                info "@openai/codex instalado com sucesso ✓"
            else
                error "Falha ao instalar @openai/codex"
                error "Verifique se o pacote está disponível no npm"
            fi
        fi
    fi
    
    # Codebuff CLI
    if [[ "$INSTALL_CODEBUFF" == "1" ]]; then
        info "Verificando Codebuff CLI..."
        
        if npm list -g --depth=0 2>/dev/null | grep -q 'codebuff'; then
            if [[ "$UPDATE_EXISTING" == "1" ]]; then
                info "Atualizando Codebuff CLI..."
                npm update -g codebuff >/dev/null 2>&1
            else
                info "Codebuff já instalado ✓"
            fi
        else
            info "Instalando Codebuff CLI..."
            if npm install -g codebuff >/dev/null 2>&1; then
                INSTALLED_PACKAGES+=("codebuff")
                info "Codebuff instalado com sucesso ✓"
            else
                error "Falha ao instalar Codebuff"
                error "Verifique se o pacote está disponível no npm"
            fi
        fi
    fi
    
    # Restaurar configurações npm
    npm config delete progress
    npm config delete loglevel
}

#-----------------------------------------------------------------------------
# Configuração pós-instalação
#-----------------------------------------------------------------------------
post_install_config() {
    info "Executando configurações pós-instalação..."
    
    # Criar diretório para configurações globais npm se não existir
    local npm_prefix=$(npm config get prefix)
    if [[ ! -d "$npm_prefix" ]]; then
        mkdir -p "$npm_prefix"
        chown -R root:root "$npm_prefix"
    fi
    
    # Verificar e corrigir permissões
    npm doctor 2>&1 | grep -v "npm ping" | grep -v "npm -v" | grep -v "node -v" || true
    
    # Limpar cache npm se solicitado
    if [[ "$CLEAN_CACHE" == "1" ]]; then
        info "Limpando cache npm..."
        npm cache clean --force >/dev/null 2>&1
    fi
    
    # Criar script de informações
    local info_script="/usr/local/bin/node-info"
    cat > "$info_script" << 'EOF'
#!/bin/bash
echo "=== Node.js Environment Info ==="
echo "Node.js: $(node -v)"
echo "npm: $(npm -v)"
echo "Global packages:"
npm list -g --depth=0 2>/dev/null | grep -E "(@openai/codex|codebuff)" | sed 's/├── /  - /g' | sed 's/└── /  - /g'
echo "npm prefix: $(npm config get prefix)"
echo "npm cache: $(npm config get cache)"
EOF
    chmod +x "$info_script"
    CREATED_RESOURCES+=("file:$info_script")
    
    info "Configurações pós-instalação concluídas ✓"
}

#-----------------------------------------------------------------------------
# Validação da instalação
#-----------------------------------------------------------------------------
verify_installation() {
    info "Validando instalação..."
    echo
    
    local all_ok=true
    
    # Verificar Node.js
    if cmd_exists node; then
        echo -e "${GREEN}✓${NC} Node.js $(node -v)"
    else
        echo -e "${RED}✗${NC} Node.js não encontrado"
        all_ok=false
    fi
    
    # Verificar npm
    if cmd_exists npm; then
        echo -e "${GREEN}✓${NC} npm $(npm -v)"
    else
        echo -e "${RED}✗${NC} npm não encontrado"
        all_ok=false
    fi
    
    # Verificar Codex CLI
    if [[ "$INSTALL_CODEX" == "1" ]]; then
        if cmd_exists codex; then
            local codex_version=$(codex --version 2>/dev/null || echo "versão desconhecida")
            echo -e "${GREEN}✓${NC} Codex CLI: $codex_version"
        else
            echo -e "${YELLOW}⚠${NC} Codex CLI: não encontrado no PATH"
            echo "  Tente: $(npm config get prefix)/bin/codex --version"
        fi
    fi
    
    # Verificar Codebuff CLI
    if [[ "$INSTALL_CODEBUFF" == "1" ]]; then
        if cmd_exists codebuff; then
            local codebuff_version=$(codebuff --version 2>/dev/null || echo "versão desconhecida")
            echo -e "${GREEN}✓${NC} Codebuff CLI: $codebuff_version"
        else
            echo -e "${YELLOW}⚠${NC} Codebuff CLI: não encontrado no PATH"
            echo "  Tente: $(npm config get prefix)/bin/codebuff --version"
        fi
    fi
    
    echo
    
    if [[ "$all_ok" == "true" ]]; then
        info "Todas as ferramentas foram instaladas com sucesso! ✓"
    else
        error "Algumas ferramentas não foram instaladas corretamente"
        exit 1
    fi
}

#-----------------------------------------------------------------------------
# Limpeza final
#-----------------------------------------------------------------------------
cleanup() {
    if [[ "$CLEAN_CACHE" == "1" ]]; then
        info "Executando limpeza..."
        
        # Limpar cache apt
        apt-get clean
        apt-get autoremove -y >/dev/null 2>&1
        
        # Limpar arquivos temporários antigos do cache
        find "$CACHE_DIR" -type f -mtime +30 -delete 2>/dev/null || true
        
        info "Limpeza concluída ✓"
    fi
}

#-----------------------------------------------------------------------------
# Mostrar resumo final
#-----------------------------------------------------------------------------
show_summary() {
    echo
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         Instalação Concluída com Sucesso! 🎉              ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    echo -e "${BLUE}Ferramentas instaladas:${NC}"
    echo " • Node.js $(node -v)"
    echo " • npm $(npm -v)"
    
    [[ "$INSTALL_CODEX" == "1" ]] && echo " • OpenAI Codex CLI"
    [[ "$INSTALL_CODEBUFF" == "1" ]] && echo " • Codebuff CLI"
    
    echo
    echo -e "${BLUE}Comandos disponíveis:${NC}"
    echo " • node-info      - Ver informações do ambiente Node.js"
    [[ "$INSTALL_CODEX" == "1" ]] && echo " • codex --help   - Ajuda do OpenAI Codex CLI"
    [[ "$INSTALL_CODEBUFF" == "1" ]] && echo " • codebuff --help - Ajuda do Codebuff CLI"
    
    echo
    echo -e "${YELLOW}Próximos passos:${NC}"
    
    if [[ "$INSTALL_CODEX" == "1" ]]; then
        echo " 1. Configure sua API key do OpenAI:"
        echo "    export OPENAI_API_KEY='sua-chave-aqui'"
    fi
    
    if [[ "$INSTALL_CODEBUFF" == "1" ]]; then
        echo " 2. Inicie o Codebuff em seu projeto:"
        echo "    cd /seu/projeto && codebuff"
    fi
    
    echo
    echo -e "${GREEN}Log completo em:${NC} $LOG_FILE"
    echo
}

#-----------------------------------------------------------------------------
# Função principal
#-----------------------------------------------------------------------------
main() {
    clear
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          Node.js & AI Tools Installer v2.0                ║"
    echo "║        Node.js + OpenAI Codex + Codebuff CLI             ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Verificações iniciais
    check_system_requirements
    check_connectivity
    
    # Instalação
    install_dependencies
    install_node
    install_cli_tools
    post_install_config
    
    # Validação e limpeza
    verify_installation
    cleanup
    
    # Mostrar resumo
    show_summary
    
    info "Script finalizado com sucesso!"
}

# Executar função principal
main "$@"
