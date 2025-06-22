#!/usr/bin/env bash
###############################################################################
# Script: master-installer.sh
# Descrição: Script mestre para instalação coordenada de todos os componentes
# Sistema-alvo: Ubuntu/Debian
# Versão: 1.0.0
# Autor: philipe_cruz@outlook.com
#
# Este script coordena a execução dos seguintes componentes:
# - Security Hardening (segurança do sistema)
# - Node.js e ferramentas AI
# - Stack WNC (Chatwoot + WAHA + n8n)
# - Stack de Monitoramento (Prometheus + Grafana)
###############################################################################

# Configuração de cores para output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m' # No Color

# Diretório de trabalho
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/var/log/master-installer"
LOG_FILE="${LOG_DIR}/installation_$(date +%Y%m%d_%H%M%S).log"
STATE_FILE="${LOG_DIR}/installation_state"

# Criar diretórios necessários
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

# Logging
log() {
    echo "$(date '+%F %T') [$1] ${@:2}" | tee -a "$LOG_FILE"
}

info() { echo -e "${GREEN}[INFO]${NC} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}[✓]${NC} $*" | tee -a "$LOG_FILE"; }

# Configurações padrão
declare -A COMPONENTS=(
    ["security"]="Security Hardening"
    ["nodejs"]="Node.js & AI Tools"
    ["wnc"]="WNC Stack (Chatwoot/WAHA/n8n)"
    ["monitoring"]="Monitoring Stack"
)

declare -A SCRIPTS=(
    ["security"]="security_hardening.sh"
    ["nodejs"]="nodejs-codex-installer.sh"
    ["wnc"]="setup-wnc.sh"
    ["monitoring"]="monitoring_setup.sh"
)

declare -A INSTALLED=()

# Verificar se script existe
check_script() {
    local script="$1"
    if [[ ! -f "${SCRIPT_DIR}/${script}" ]]; then
        error "Script não encontrado: ${script}"
        return 1
    fi
    if [[ ! -x "${SCRIPT_DIR}/${script}" ]]; then
        chmod +x "${SCRIPT_DIR}/${script}"
    fi
    return 0
}

# Salvar estado da instalação
save_state() {
    {
        echo "# Estado da instalação - $(date)"
        for component in "${!INSTALLED[@]}"; do
            echo "${component}=${INSTALLED[$component]}"
        done
    } > "$STATE_FILE"
}

# Carregar estado da instalação
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        while IFS='=' read -r key value; do
            [[ "$key" =~ ^#.*$ ]] && continue
            [[ -z "$key" ]] && continue
            INSTALLED["$key"]="$value"
        done < "$STATE_FILE"
    fi
}

# Verificar requisitos do sistema
check_system() {
    info "Verificando requisitos do sistema..."
    
    # Root check
    if [[ $EUID -ne 0 ]]; then
        error "Este script deve ser executado como root (use sudo)"
        exit 1
    fi
    
    # OS check
    if ! grep -qi "ubuntu\|debian" /etc/os-release 2>/dev/null; then
        warn "Sistema não é Ubuntu/Debian"
    fi
    
    # Memória
    local mem_total=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $mem_total -lt 4 ]]; then
        warn "Memória disponível: ${mem_total}GB (recomendado: 4GB+)"
    fi
    
    # Disco
    local disk_free=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $disk_free -lt 20 ]]; then
        warn "Espaço em disco: ${disk_free}GB (recomendado: 20GB+)"
    fi
    
    success "Verificação do sistema concluída"
}

# Menu interativo
show_menu() {
    clear
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              Master Installer - WNC Stack                  ║"
    echo "║                    Versão 1.0.0                           ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "${CYAN}Componentes disponíveis:${NC}"
    echo
    
    local i=1
    for key in security nodejs wnc monitoring; do
        local status=""
        if [[ "${INSTALLED[$key]}" == "true" ]]; then
            status="${GREEN}[Instalado]${NC}"
        else
            status="${YELLOW}[Pendente]${NC}"
        fi
        echo -e "  $i) ${COMPONENTS[$key]} $status"
        ((i++))
    done
    
    echo
    echo -e "  ${MAGENTA}A) Instalar TODOS os componentes${NC}"
    echo -e "  ${CYAN}R) Executar instalação recomendada${NC}"
    echo -e "  ${YELLOW}S) Status da instalação${NC}"
    echo -e "  ${RED}Q) Sair${NC}"
    echo
}

# Executar script de instalação
run_installer() {
    local component="$1"
    local script="${SCRIPTS[$component]}"
    
    if ! check_script "$script"; then
        return 1
    fi
    
    info "Iniciando instalação: ${COMPONENTS[$component]}"
    echo
    
    # Executar script
    if "${SCRIPT_DIR}/${script}"; then
        INSTALLED["$component"]="true"
        save_state
        success "${COMPONENTS[$component]} instalado com sucesso!"
        return 0
    else
        error "Falha na instalação de ${COMPONENTS[$component]}"
        return 1
    fi
}

# Instalação recomendada (ordem otimizada)
recommended_install() {
    info "Executando instalação na ordem recomendada..."
    echo
    
    local order=("security" "nodejs" "wnc" "monitoring")
    local failed=0
    
    for component in "${order[@]}"; do
        if [[ "${INSTALLED[$component]}" == "true" ]]; then
            info "${COMPONENTS[$component]} já está instalado - pulando"
            continue
        fi
        
        echo
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}Instalando: ${COMPONENTS[$component]}${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo
        
        if ! run_installer "$component"; then
            ((failed++))
            warn "Continuando com próximo componente..."
        fi
        
        # Pausa entre instalações
        if [[ "$component" != "${order[-1]}" ]]; then
            echo
            read -p "Pressione ENTER para continuar com o próximo componente..."
        fi
    done
    
    echo
    if [[ $failed -eq 0 ]]; then
        success "Instalação recomendada concluída com sucesso!"
    else
        warn "Instalação concluída com $failed erro(s)"
    fi
}

# Instalar todos os componentes
install_all() {
    recommended_install
}

# Mostrar status da instalação
show_status() {
    clear
    echo -e "${BLUE}=== Status da Instalação ===${NC}"
    echo
    
    for key in security nodejs wnc monitoring; do
        if [[ "${INSTALLED[$key]}" == "true" ]]; then
            echo -e "${GREEN}✓${NC} ${COMPONENTS[$key]}"
        else
            echo -e "${RED}✗${NC} ${COMPONENTS[$key]}"
        fi
    done
    
    echo
    echo "Logs salvos em: $LOG_DIR"
    echo
    
    # Verificar serviços principais
    echo -e "${BLUE}=== Status dos Serviços ===${NC}"
    echo
    
    # SSH
    if systemctl is-active --quiet sshd; then
        echo -e "${GREEN}✓${NC} SSH"
    else
        echo -e "${RED}✗${NC} SSH"
    fi
    
    # Docker
    if systemctl is-active --quiet docker; then
        echo -e "${GREEN}✓${NC} Docker"
        
        # Containers Docker
        echo
        echo "Containers rodando:"
        docker ps --format "table {{.Names}}\t{{.Status}}" | grep -v "^NAMES" | sed 's/^/  /'
    fi
    
    # Nginx
    if systemctl is-active --quiet nginx; then
        echo -e "${GREEN}✓${NC} Nginx"
    fi
    
    # Node.js
    if command -v node &>/dev/null; then
        echo -e "${GREEN}✓${NC} Node.js $(node -v)"
    fi
    
    echo
    read -p "Pressione ENTER para voltar ao menu..."
}

# Função de ajuda
show_help() {
    cat <<EOF
Uso: $0 [OPÇÕES]

OPÇÕES:
    -h, --help          Mostrar esta ajuda
    -a, --all           Instalar todos os componentes
    -r, --recommended   Executar instalação recomendada
    -s, --status        Mostrar status da instalação
    --security          Instalar apenas Security Hardening
    --nodejs            Instalar apenas Node.js & AI Tools
    --wnc               Instalar apenas WNC Stack
    --monitoring        Instalar apenas Monitoring Stack

EXEMPLOS:
    $0                  # Menu interativo
    $0 --all            # Instalar tudo
    $0 --security       # Instalar apenas segurança
    $0 --status         # Ver status

EOF
}

# Processar argumentos de linha de comando
process_args() {
    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -a|--all)
            check_system
            install_all
            exit 0
            ;;
        -r|--recommended)
            check_system
            recommended_install
            exit 0
            ;;
        -s|--status)
            load_state
            show_status
            exit 0
            ;;
        --security)
            check_system
            run_installer "security"
            exit $?
            ;;
        --nodejs)
            check_system
            run_installer "nodejs"
            exit $?
            ;;
        --wnc)
            check_system
            run_installer "wnc"
            exit $?
            ;;
        --monitoring)
            check_system
            run_installer "monitoring"
            exit $?
            ;;
    esac
}

# Menu principal
main_menu() {
    while true; do
        show_menu
        read -p "Selecione uma opção: " choice
        
        case "$choice" in
            1)
                run_installer "security"
                read -p "Pressione ENTER para continuar..."
                ;;
            2)
                run_installer "nodejs"
                read -p "Pressione ENTER para continuar..."
                ;;
            3)
                run_installer "wnc"
                read -p "Pressione ENTER para continuar..."
                ;;
            4)
                run_installer "monitoring"
                read -p "Pressione ENTER para continuar..."
                ;;
            [Aa])
                install_all
                read -p "Pressione ENTER para continuar..."
                ;;
            [Rr])
                recommended_install
                read -p "Pressione ENTER para continuar..."
                ;;
            [Ss])
                show_status
                ;;
            [Qq])
                info "Saindo..."
                exit 0
                ;;
            *)
                error "Opção inválida!"
                sleep 2
                ;;
        esac
    done
}

# Função principal
main() {
    # Processar argumentos
    process_args "$@"
    
    # Verificar sistema
    check_system
    
    # Carregar estado
    load_state
    
    # Mostrar aviso inicial
    clear
    echo -e "${YELLOW}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                         ATENÇÃO                            ║"
    echo "║                                                            ║"
    echo "║  Este instalador fará alterações significativas no        ║"
    echo "║  sistema, incluindo:                                       ║"
    echo "║                                                            ║"
    echo "║  • Configurações de segurança (SSH, Firewall)             ║"
    echo "║  • Instalação de pacotes e serviços                       ║"
    echo "║  • Criação de containers Docker                           ║"
    echo "║  • Modificação de configurações do sistema                ║"
    echo "║                                                            ║"
    echo "║  Recomenda-se executar em um sistema novo ou de teste    ║"
    echo "║  primeiro!                                                 ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
    read -p "Deseja continuar? [s/N]: " -r
    
    if [[ ! "$REPLY" =~ ^[Ss]$ ]]; then
        info "Instalação cancelada"
        exit 0
    fi
    
    # Iniciar menu
    main_menu
}

# Executar
main "$@"