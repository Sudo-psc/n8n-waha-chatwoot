#!/usr/bin/env bash
###############################################################################
# Script: security_hardening.sh
# Descrição: Aplica configurações de segurança e hardening no sistema
# Sistema-alvo: Ubuntu/Debian
# Versão: 2.0.0
# Autor: philipe_cruz@outlook.com
#
# Melhorias v2.0:
# - Validações de sistema e compatibilidade
# - Configurações modulares de segurança
# - Sistema de rollback em caso de falha
# - Hardening de kernel via sysctl
# - Configuração avançada de firewall
# - Auditoria com auditd
# - Proteção contra ataques comuns
###############################################################################

# Configuração de cores para output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Structured logging
SCRIPT_NAME=$(basename "$0" .sh)
LOG_FILE="/var/log/${SCRIPT_NAME}.log"
BACKUP_DIR="/var/backups/${SCRIPT_NAME}"
REPORT_FILE="/var/log/${SCRIPT_NAME}_report_$(date +%Y%m%d_%H%M%S).txt"

mkdir -p "$(dirname "$LOG_FILE")" "$BACKUP_DIR"
touch "$LOG_FILE" "$REPORT_FILE"

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
declare -a BACKUP_FILES=()

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
    info "Executando rollback das alterações..."
    
    # Restaurar arquivos de backup
    for backup in "${BACKUP_FILES[@]}"; do
        local original="${backup%.bak.*}"
        if [[ -f "$backup" ]]; then
            info "Restaurando: $original"
            cp "$backup" "$original"
        fi
    done
    
    # Remover recursos criados
    for resource in "${CREATED_RESOURCES[@]}"; do
        case "$resource" in
            "file:*")
                local file="${resource#file:}"
                [[ -f "$file" ]] && rm -f "$file"
                ;;
            "service:*")
                local service="${resource#service:}"
                systemctl stop "$service" 2>/dev/null || true
                systemctl disable "$service" 2>/dev/null || true
                ;;
            "package:*")
                local package="${resource#package:}"
                apt-get remove -y "$package" 2>/dev/null || true
                ;;
        esac
    done
    
    info "Rollback concluído"
}

# Configurações padrão (podem ser sobrescritas por variáveis de ambiente)
: "${ENABLE_UNATTENDED_UPGRADES:=1}"
: "${ENABLE_SSH_HARDENING:=1}"
: "${ENABLE_FAIL2BAN:=1}"
: "${ENABLE_FIREWALL:=1}"
: "${ENABLE_KERNEL_HARDENING:=1}"
: "${ENABLE_AUDITD:=1}"
: "${ENABLE_APPARMOR:=1}"
: "${ENABLE_ROOTKIT_HUNTER:=1}"
: "${ENABLE_AIDE:=0}"
: "${ENABLE_NETWORK_HARDENING:=1}"
: "${SSH_PORT:=22}"
: "${ALLOW_SSH_ROOT:=0}"
: "${ALLOW_PASSWORD_AUTH:=0}"
: "${FAIL2BAN_MAXRETRY:=3}"
: "${FAIL2BAN_BANTIME:=3600}"
: "${INTERACTIVE:=1}"

#-----------------------------------------------------------------------------
# Funções utilitárias
#-----------------------------------------------------------------------------
cmd_exists() { 
    command -v "$1" &>/dev/null 
}

backup_file() {
    local file=$1
    if [[ -f "$file" ]]; then
        local backup="${BACKUP_DIR}/$(basename "$file").bak.$(date +%s)"
        cp -a "$file" "$backup"
        BACKUP_FILES+=("$backup")
        debug "Backup criado: $backup"
    fi
}

write_config() {
    local file=$1
    shift
    
    backup_file "$file"
    cat > "$file" "$@"
    CREATED_RESOURCES+=("file:$file")
}

append_if_not_exists() {
    local file=$1
    local line=$2
    
    if ! grep -qF "$line" "$file" 2>/dev/null; then
        echo "$line" >> "$file"
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
        warn "Sistema: $ID $VERSION_ID"
        warn "Este script foi testado apenas em Ubuntu/Debian"
        
        if [[ "$INTERACTIVE" == "1" ]]; then
            read -p "Deseja continuar mesmo assim? [s/N]: " -r
            if [[ ! "$REPLY" =~ ^[Ss]$ ]]; then
                info "Instalação cancelada"
                exit 0
            fi
        fi
    fi
    
    # Verificar conectividade
    if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        warn "Sem conectividade com a internet. Algumas funcionalidades podem não funcionar."
    fi
    
    info "Sistema: $PRETTY_NAME"
    info "Kernel: $(uname -r)"
    info "Arquitetura: $(uname -m)"
    info "Requisitos verificados ✓"
}

#-----------------------------------------------------------------------------
# Análise de segurança inicial
#-----------------------------------------------------------------------------
security_audit() {
    info "Realizando auditoria de segurança inicial..."
    
    {
        echo "=== RELATÓRIO DE SEGURANÇA ==="
        echo "Data: $(date)"
        echo "Sistema: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
        echo "Kernel: $(uname -r)"
        echo
        
        echo "=== USUÁRIOS ==="
        echo "Usuários com UID 0 (root):"
        awk -F: '($3 == "0") {print "  - " $1}' /etc/passwd
        echo
        
        echo "Usuários com shell válido:"
        grep -vE '(nologin|false)$' /etc/passwd | cut -d: -f1 | sed 's/^/  - /'
        echo
        
        echo "=== SERVIÇOS ==="
        echo "Serviços ativos:"
        systemctl list-units --type=service --state=active --no-pager | grep ".service" | awk '{print "  - " $1}'
        echo
        
        echo "Portas abertas:"
        ss -tlnp 2>/dev/null | grep LISTEN | awk '{print "  - " $4}' | sort -u
        echo
        
        echo "=== SSH ==="
        if [[ -f /etc/ssh/sshd_config ]]; then
            echo "PermitRootLogin: $(grep -E "^PermitRootLogin" /etc/ssh/sshd_config || echo "não definido")"
            echo "PasswordAuthentication: $(grep -E "^PasswordAuthentication" /etc/ssh/sshd_config || echo "não definido")"
            echo "Port: $(grep -E "^Port" /etc/ssh/sshd_config || echo "22 (padrão)")"
        fi
        echo
        
        echo "=== FIREWALL ==="
        if cmd_exists ufw; then
            echo "UFW Status: $(ufw status | head -1)"
        else
            echo "UFW: não instalado"
        fi
        
        if cmd_exists iptables; then
            echo "Regras iptables: $(iptables -L 2>/dev/null | grep -c "^Chain" || echo "0") chains"
        fi
        echo
        
        echo "=== ATUALIZAÇÕES ==="
        echo "Pacotes atualizáveis: $(apt list --upgradable 2>/dev/null | grep -c "upgradable" || echo "desconhecido")"
        echo
        
    } >> "$REPORT_FILE"
    
    info "Auditoria concluída. Relatório salvo em: $REPORT_FILE"
}

#-----------------------------------------------------------------------------
# Configuração de atualizações automáticas
#-----------------------------------------------------------------------------
setup_unattended_upgrades() {
    if [[ "$ENABLE_UNATTENDED_UPGRADES" != "1" ]]; then
        return
    fi
    
    info "Configurando atualizações automáticas de segurança..."
    
    # Instalar pacote
    DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades apt-listchanges >/dev/null 2>&1
    CREATED_RESOURCES+=("package:unattended-upgrades")
    
    # Configurar
    write_config /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

Unattended-Upgrade::DevRelease "false";
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::InstallOnShutdown "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
EOF

    write_config /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    # Ativar serviço
    systemctl enable unattended-upgrades
    systemctl start unattended-upgrades
    
    info "Atualizações automáticas configuradas ✓"
}

#-----------------------------------------------------------------------------
# Hardening do SSH
#-----------------------------------------------------------------------------
harden_ssh() {
    if [[ "$ENABLE_SSH_HARDENING" != "1" ]]; then
        return
    fi
    
    info "Aplicando hardening no SSH..."
    
    # Backup da configuração
    backup_file /etc/ssh/sshd_config
    
    # Aplicar configurações de segurança
    cat > /etc/ssh/sshd_config.d/99-hardening.conf <<EOF
# Security hardening settings
Protocol 2
Port ${SSH_PORT}

# Authentication
PermitRootLogin $([ "$ALLOW_SSH_ROOT" == "1" ] && echo "without-password" || echo "no")
PasswordAuthentication $([ "$ALLOW_PASSWORD_AUTH" == "1" ] && echo "yes" || echo "no")
PubkeyAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Security
StrictModes yes
IgnoreRhosts yes
HostbasedAuthentication no
X11Forwarding no
PermitUserEnvironment no
AllowAgentForwarding no
AllowTcpForwarding no
PermitTunnel no

# Login restrictions
LoginGraceTime 30s
MaxAuthTries 3
MaxSessions 2
MaxStartups 10:30:60

# Crypto
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512

# Logging
LogLevel VERBOSE
SyslogFacility AUTH

# Idle timeout
ClientAliveInterval 300
ClientAliveCountMax 2
TCPKeepAlive no

# Banner
Banner /etc/issue.net
EOF

    # Criar banner de aviso
    write_config /etc/issue.net <<'EOF'
****************************************************************************
*                            AVISO DE SEGURANÇA                            *
*                                                                          *
* Este sistema é para uso autorizado apenas. Todas as atividades são      *
* monitoradas e registradas. O acesso não autorizado é estritamente       *
* proibido e será reportado às autoridades competentes.                   *
*                                                                          *
****************************************************************************
EOF

    # Gerar novas chaves do host se solicitado
    if [[ "${REGENERATE_HOST_KEYS:-0}" == "1" ]]; then
        info "Regenerando chaves do host SSH..."
        rm -f /etc/ssh/ssh_host_*
        ssh-keygen -A
    fi
    
    # Validar configuração
    if sshd -t; then
        systemctl reload sshd
        info "SSH hardening aplicado ✓"
        
        if [[ "$SSH_PORT" != "22" ]]; then
            warn "SSH agora está na porta $SSH_PORT. Atualize suas conexões!"
        fi
    else
        error "Configuração SSH inválida. Verifique os logs."
        exit 1
    fi
}

#-----------------------------------------------------------------------------
# Configuração do Fail2Ban
#-----------------------------------------------------------------------------
setup_fail2ban() {
    if [[ "$ENABLE_FAIL2BAN" != "1" ]]; then
        return
    fi
    
    info "Configurando Fail2Ban..."
    
    # Instalar
    apt-get install -y fail2ban >/dev/null 2>&1
    CREATED_RESOURCES+=("package:fail2ban")
    
    # Configuração principal
    write_config /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = ${FAIL2BAN_BANTIME}
findtime = 600
maxretry = ${FAIL2BAN_MAXRETRY}
destemail = root@localhost
sendername = Fail2Ban
action = %(action_mwl)s

# Proteção contra scan de portas
banaction = iptables-multiport
protocol = tcp
chain = INPUT

[sshd]
enabled = true
port = ${SSH_PORT}
filter = sshd
logpath = /var/log/auth.log
maxretry = ${FAIL2BAN_MAXRETRY}

[sshd-ddos]
enabled = true
port = ${SSH_PORT}
filter = sshd-ddos
logpath = /var/log/auth.log
maxretry = 2

[nginx-http-auth]
enabled = true
port = http,https
filter = nginx-http-auth
logpath = /var/log/nginx/error.log

[nginx-noscript]
enabled = true
port = http,https
filter = nginx-noscript
logpath = /var/log/nginx/access.log
maxretry = 6

[nginx-badbots]
enabled = true
port = http,https
filter = nginx-badbots
logpath = /var/log/nginx/access.log
maxretry = 2

[nginx-noproxy]
enabled = true
port = http,https
filter = nginx-noproxy
logpath = /var/log/nginx/access.log
maxretry = 2
EOF

    # Criar filtro para DDoS SSH
    write_config /etc/fail2ban/filter.d/sshd-ddos.conf <<'EOF'
[Definition]
failregex = ^%(__prefix_line)sDid not receive identification string from <HOST>$
            ^%(__prefix_line)sReceived disconnect from <HOST>.*: 11: Bye Bye \[preauth\]$
            ^%(__prefix_line)sConnection reset by <HOST> port \d+ \[preauth\]$
ignoreregex =
EOF

    # Criar filtro para bad bots
    write_config /etc/fail2ban/filter.d/nginx-badbots.conf <<'EOF'
[Definition]
badbots = Semrush|Bytespider|AhrefsBot|DotBot|MJ12bot|SeznamBot|BLEXBot|BlexBot
failregex = ^<HOST> -.*"(GET|POST|HEAD).*HTTP.*".*(?:%(badbots)s).*"$
ignoreregex =
EOF

    # Criar filtro para proxy requests
    write_config /etc/fail2ban/filter.d/nginx-noproxy.conf <<'EOF'
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD|CONNECT) (https?://|[a-zA-Z0-9\.-]+:[0-9]+/).*HTTP.*"$
ignoreregex =
EOF

    # Reiniciar serviço
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    # Verificar status
    sleep 2
    fail2ban-client status
    
    info "Fail2Ban configurado ✓"
}

#-----------------------------------------------------------------------------
# Configuração do Firewall (UFW)
#-----------------------------------------------------------------------------
setup_firewall() {
    if [[ "$ENABLE_FIREWALL" != "1" ]]; then
        return
    fi
    
    info "Configurando firewall UFW..."
    
    # Instalar UFW
    apt-get install -y ufw >/dev/null 2>&1
    
    # Configuração básica
    ufw --force disable
    ufw default deny incoming
    ufw default allow outgoing
    ufw default deny forward
    
    # Logging
    ufw logging medium
    
    # Permitir SSH (com rate limiting)
    ufw limit ${SSH_PORT}/tcp comment "SSH rate limited"
    
    # Permitir serviços web se nginx estiver instalado
    if systemctl is-active --quiet nginx; then
        ufw allow 80/tcp comment "HTTP"
        ufw allow 443/tcp comment "HTTPS"
    fi
    
    # Permitir DNS
    ufw allow out 53/udp comment "DNS"
    
    # Permitir NTP
    ufw allow out 123/udp comment "NTP"
    
    # Proteção contra ataques comuns
    cat > /etc/ufw/before.rules.new <<'EOF'
# Proteção contra ataques de inundação ICMP
-A ufw-before-input -p icmp --icmp-type echo-request -m limit --limit 10/minute --limit-burst 5 -j ACCEPT
-A ufw-before-input -p icmp --icmp-type echo-request -j DROP

# Proteção contra pacotes inválidos
-A ufw-before-input -m conntrack --ctstate INVALID -j DROP

# Proteção contra SYN flood
-A ufw-before-input -p tcp --syn -m limit --limit 20/second --limit-burst 50 -j ACCEPT
-A ufw-before-input -p tcp --syn -j DROP

# Proteção contra port scanning
-A ufw-before-input -p tcp --tcp-flags ALL NONE -j DROP
-A ufw-before-input -p tcp --tcp-flags ALL ALL -j DROP
-A ufw-before-input -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP
-A ufw-before-input -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
-A ufw-before-input -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
EOF
    
    # Adicionar regras ao arquivo existente
    if grep -q "# Proteção contra ataques" /etc/ufw/before.rules; then
        debug "Regras de proteção já existem"
    else
        # Inserir regras antes do COMMIT final
        sed -i '/^COMMIT/i\
# Proteção contra ataques de inundação ICMP\
-A ufw-before-input -p icmp --icmp-type echo-request -m limit --limit 10/minute --limit-burst 5 -j ACCEPT\
-A ufw-before-input -p icmp --icmp-type echo-request -j DROP\
\
# Proteção contra pacotes inválidos\
-A ufw-before-input -m conntrack --ctstate INVALID -j DROP\
\
# Proteção contra SYN flood\
-A ufw-before-input -p tcp --syn -m limit --limit 20/second --limit-burst 50 -j ACCEPT\
-A ufw-before-input -p tcp --syn -j DROP\
\
# Proteção contra port scanning\
-A ufw-before-input -p tcp --tcp-flags ALL NONE -j DROP\
-A ufw-before-input -p tcp --tcp-flags ALL ALL -j DROP\
-A ufw-before-input -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP\
-A ufw-before-input -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP\
-A ufw-before-input -p tcp --tcp-flags SYN,RST SYN,RST -j DROP\
' /etc/ufw/before.rules
    fi
    
    # Habilitar firewall
    ufw --force enable
    
    info "Firewall UFW configurado ✓"
    ufw status verbose
}

#-----------------------------------------------------------------------------
# Hardening do Kernel
#-----------------------------------------------------------------------------
harden_kernel() {
    if [[ "$ENABLE_KERNEL_HARDENING" != "1" ]]; then
        return
    fi
    
    info "Aplicando hardening no kernel..."
    
    # Backup sysctl.conf
    backup_file /etc/sysctl.conf
    
    # Criar arquivo de hardening
    write_config /etc/sysctl.d/99-security-hardening.conf <<'EOF'
# Kernel hardening parameters

# Proteção contra IP spoofing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignorar respostas ICMP bogus
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Não aceitar source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Não aceitar pacotes ICMP redirect
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0

# Não enviar pacotes ICMP redirect
net.ipv4.conf.all.send_redirects = 0

# Proteção contra SYN flood
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Log de pacotes suspeitos
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignorar ping broadcasts
net.ipv4.icmp_echo_ignore_all = 0

# Desabilitar IPv6 se não usado
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0

# Kernel hardening
kernel.randomize_va_space = 2
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
kernel.core_uses_pid = 1
kernel.sysrq = 0
kernel.exec-shield = 1

# Dmesg restriction
kernel.dmesg_restrict = 1

# Proteção de memória
vm.mmap_min_addr = 65536
vm.swappiness = 10

# Proteção contra fork bomb
kernel.pid_max = 65536

# Limitar core dumps
fs.suid_dumpable = 0

# Aumentar limites de arquivo
fs.file-max = 65535

# Proteção de links simbólicos
fs.protected_hardlinks = 1
fs.protected_symlinks = 1

# TCP hardening
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_fin_timeout = 20
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 15

# Limites de conexão
net.core.somaxconn = 1024
net.ipv4.tcp_max_tw_buckets = 1440000
net.core.netdev_max_backlog = 5000
EOF

    # Aplicar configurações
    sysctl -p /etc/sysctl.d/99-security-hardening.conf >/dev/null 2>&1
    
    info "Kernel hardening aplicado ✓"
}

#-----------------------------------------------------------------------------
# Configuração do Auditd
#-----------------------------------------------------------------------------
setup_auditd() {
    if [[ "$ENABLE_AUDITD" != "1" ]]; then
        return
    fi
    
    info "Configurando sistema de auditoria (auditd)..."
    
    # Instalar auditd
    apt-get install -y auditd audispd-plugins >/dev/null 2>&1
    CREATED_RESOURCES+=("package:auditd")
    
    # Configurar regras de auditoria
    write_config /etc/audit/rules.d/hardening.rules <<'EOF'
# Limpar regras anteriores
-D

# Buffer
-b 8192

# Failure mode
-f 1

# Monitorar alterações em arquivos de sistema
-w /etc/passwd -p wa -k passwd_changes
-w /etc/group -p wa -k group_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/sudoers.d/ -p wa -k sudoers_changes

# Monitorar configurações SSH
-w /etc/ssh/sshd_config -p wa -k sshd_config

# Monitorar binários críticos
-w /usr/bin/passwd -p x -k passwd_modification
-w /usr/bin/sudo -p x -k sudo_modification
-w /bin/su -p x -k su_modification

# Monitorar login/logout
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /var/log/tallylog -p wa -k logins

# Monitorar modificações de horário
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time_change
-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time_change
-a always,exit -F arch=b64 -S clock_settime -k time_change
-a always,exit -F arch=b32 -S clock_settime -k time_change

# Monitorar montagem de sistemas de arquivos
-a always,exit -F arch=b64 -S mount -S umount2 -k mounts
-a always,exit -F arch=b32 -S mount -S umount -S umount2 -k mounts

# Monitorar exclusão de arquivos
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete
-a always,exit -F arch=b32 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete

# Monitorar acesso a arquivos não autorizados
-a always,exit -F arch=b64 -S open -S openat -F exit=-EACCES -k access_denied
-a always,exit -F arch=b64 -S open -S openat -F exit=-EPERM -k access_denied
-a always,exit -F arch=b32 -S open -S openat -F exit=-EACCES -k access_denied
-a always,exit -F arch=b32 -S open -S openat -F exit=-EPERM -k access_denied

# Fazer regras imutáveis
-e 2
EOF

    # Reiniciar auditd
    systemctl enable auditd
    service auditd restart
    
    info "Sistema de auditoria configurado ✓"
}

#-----------------------------------------------------------------------------
# Configuração do AppArmor
#-----------------------------------------------------------------------------
setup_apparmor() {
    if [[ "$ENABLE_APPARMOR" != "1" ]]; then
        return
    fi
    
    info "Configurando AppArmor..."
    
    # Instalar AppArmor e utilitários
    apt-get install -y apparmor apparmor-utils apparmor-profiles apparmor-profiles-extra >/dev/null 2>&1
    
    # Habilitar AppArmor
    systemctl enable apparmor
    systemctl start apparmor
    
    # Colocar perfis em modo enforce
    aa-enforce /etc/apparmor.d/* 2>/dev/null || true
    
    # Status
    aa-status
    
    info "AppArmor configurado ✓"
}

#-----------------------------------------------------------------------------
# Instalação do Rootkit Hunter
#-----------------------------------------------------------------------------
setup_rkhunter() {
    if [[ "$ENABLE_ROOTKIT_HUNTER" != "1" ]]; then
        return
    fi
    
    info "Instalando Rootkit Hunter..."
    
    # Instalar rkhunter
    apt-get install -y rkhunter >/dev/null 2>&1
    CREATED_RESOURCES+=("package:rkhunter")
    
    # Atualizar base de dados
    rkhunter --update >/dev/null 2>&1 || true
    rkhunter --propupd >/dev/null 2>&1
    
    # Configurar
    write_config /etc/rkhunter.conf.local <<'EOF'
# Configurações locais do rkhunter
MAIL-ON-WARNING=root
MAIL_CMD=mail -s "[rkhunter] Warnings found for ${HOST_NAME}"
COPY_LOG_ON_ERROR=1
PKGMGR=DPKG
USE_SYSLOG=authpriv.warning
AUTO_X_DETECT=1
ALLOW_SSH_ROOT_USER=no
ALLOW_SSH_PROT_V1=0
EOF

    # Criar cron job para verificação diária
    write_config /etc/cron.daily/rkhunter-check <<'EOF'
#!/bin/bash
/usr/bin/rkhunter --cronjob --report-warnings-only
EOF
    chmod +x /etc/cron.daily/rkhunter-check
    
    info "Rootkit Hunter instalado ✓"
}

#-----------------------------------------------------------------------------
# Configuração do AIDE
#-----------------------------------------------------------------------------
setup_aide() {
    if [[ "$ENABLE_AIDE" != "1" ]]; then
        return
    fi
    
    info "Instalando AIDE (Advanced Intrusion Detection Environment)..."
    
    # Instalar AIDE
    apt-get install -y aide aide-common >/dev/null 2>&1
    CREATED_RESOURCES+=("package:aide")
    
    # Inicializar banco de dados
    info "Inicializando banco de dados AIDE (pode demorar)..."
    aideinit >/dev/null 2>&1
    
    # Copiar banco de dados
    cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
    
    # Criar cron job
    write_config /etc/cron.daily/aide-check <<'EOF'
#!/bin/bash
/usr/bin/aide --check | mail -s "[AIDE] Report for $(hostname)" root
EOF
    chmod +x /etc/cron.daily/aide-check
    
    info "AIDE instalado ✓"
}

#-----------------------------------------------------------------------------
# Hardening de rede
#-----------------------------------------------------------------------------
harden_network() {
    if [[ "$ENABLE_NETWORK_HARDENING" != "1" ]]; then
        return
    fi
    
    info "Aplicando hardening de rede..."
    
    # Desabilitar protocolos desnecessários
    write_config /etc/modprobe.d/blacklist-rare-network.conf <<'EOF'
# Protocolos de rede raramente usados
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
EOF

    # Configurar hosts.allow e hosts.deny
    write_config /etc/hosts.allow <<EOF
# Permitir SSH apenas de IPs específicos (ajuste conforme necessário)
# sshd: 192.168.1.0/24
# sshd: 10.0.0.0/8

# Permitir todos os serviços locais
ALL: 127.0.0.1
ALL: ::1
EOF

    write_config /etc/hosts.deny <<'EOF'
# Negar todo o resto
ALL: ALL
EOF

    # Proteger arquivos de configuração de rede
    chmod 644 /etc/hosts.allow
    chmod 644 /etc/hosts.deny
    
    info "Hardening de rede aplicado ✓"
}

#-----------------------------------------------------------------------------
# Limpeza e configurações finais
#-----------------------------------------------------------------------------
final_cleanup() {
    info "Executando limpeza e configurações finais..."
    
    # Remover pacotes desnecessários
    apt-get autoremove -y >/dev/null 2>&1
    apt-get autoclean -y >/dev/null 2>&1
    
    # Desabilitar serviços desnecessários
    local unnecessary_services=(
        "bluetooth"
        "cups"
        "avahi-daemon"
        "isc-dhcp-server"
        "isc-dhcp-server6"
        "rpcbind"
        "rsync"
        "nfs-server"
    )
    
    for service in "${unnecessary_services[@]}"; do
        if systemctl is-enabled "$service" &>/dev/null; then
            systemctl disable "$service" 2>/dev/null || true
            systemctl stop "$service" 2>/dev/null || true
            info "Serviço $service desabilitado"
        fi
    done
    
    # Definir permissões seguras em arquivos críticos
    chmod 644 /etc/passwd
    chmod 644 /etc/group
    chmod 600 /etc/shadow
    chmod 600 /etc/gshadow
    chmod 644 /etc/ssh/ssh_config
    chmod 600 /etc/ssh/sshd_config
    
    # Criar diretório para logs de segurança
    mkdir -p /var/log/security
    chmod 750 /var/log/security
    
    info "Limpeza concluída ✓"
}

#-----------------------------------------------------------------------------
# Verificação final
#-----------------------------------------------------------------------------
final_check() {
    info "Executando verificação final..."
    echo
    
    local all_ok=true
    
    # Verificar serviços de segurança
    echo -e "${BLUE}Status dos serviços de segurança:${NC}"
    
    # SSH
    if systemctl is-active --quiet sshd; then
        echo -e "${GREEN}✓${NC} SSH (porta $SSH_PORT)"
    else
        echo -e "${RED}✗${NC} SSH não está ativo"
        all_ok=false
    fi
    
    # Fail2Ban
    if [[ "$ENABLE_FAIL2BAN" == "1" ]]; then
        if systemctl is-active --quiet fail2ban; then
            echo -e "${GREEN}✓${NC} Fail2Ban"
        else
            echo -e "${RED}✗${NC} Fail2Ban não está ativo"
            all_ok=false
        fi
    fi
    
    # UFW
    if [[ "$ENABLE_FIREWALL" == "1" ]]; then
        if ufw status | grep -q "Status: active"; then
            echo -e "${GREEN}✓${NC} Firewall (UFW)"
        else
            echo -e "${RED}✗${NC} Firewall não está ativo"
            all_ok=false
        fi
    fi
    
    # Auditd
    if [[ "$ENABLE_AUDITD" == "1" ]]; then
        if systemctl is-active --quiet auditd; then
            echo -e "${GREEN}✓${NC} Auditd"
        else
            echo -e "${RED}✗${NC} Auditd não está ativo"
            all_ok=false
        fi
    fi
    
    # AppArmor
    if [[ "$ENABLE_APPARMOR" == "1" ]]; then
        if systemctl is-active --quiet apparmor; then
            echo -e "${GREEN}✓${NC} AppArmor"
        else
            echo -e "${RED}✗${NC} AppArmor não está ativo"
            all_ok=false
        fi
    fi
    
    echo
    return $([[ "$all_ok" == "true" ]] && echo 0 || echo 1)
}

#-----------------------------------------------------------------------------
# Gerar relatório final
#-----------------------------------------------------------------------------
generate_final_report() {
    {
        echo
        echo "=== RELATÓRIO FINAL DE HARDENING ==="
        echo "Data: $(date)"
        echo
        
        echo "Configurações aplicadas:"
        [[ "$ENABLE_UNATTENDED_UPGRADES" == "1" ]] && echo "  ✓ Atualizações automáticas de segurança"
        [[ "$ENABLE_SSH_HARDENING" == "1" ]] && echo "  ✓ SSH hardening (porta $SSH_PORT)"
        [[ "$ENABLE_FAIL2BAN" == "1" ]] && echo "  ✓ Fail2Ban (proteção contra brute force)"
        [[ "$ENABLE_FIREWALL" == "1" ]] && echo "  ✓ Firewall UFW"
        [[ "$ENABLE_KERNEL_HARDENING" == "1" ]] && echo "  ✓ Kernel hardening (sysctl)"
        [[ "$ENABLE_AUDITD" == "1" ]] && echo "  ✓ Sistema de auditoria (auditd)"
        [[ "$ENABLE_APPARMOR" == "1" ]] && echo "  ✓ AppArmor (MAC)"
        [[ "$ENABLE_ROOTKIT_HUNTER" == "1" ]] && echo "  ✓ Rootkit Hunter"
        [[ "$ENABLE_AIDE" == "1" ]] && echo "  ✓ AIDE (detecção de intrusão)"
        [[ "$ENABLE_NETWORK_HARDENING" == "1" ]] && echo "  ✓ Hardening de rede"
        echo
        
        echo "Arquivos de backup salvos em: $BACKUP_DIR"
        echo "Logs do script em: $LOG_FILE"
        echo
        
        echo "IMPORTANTE:"
        echo "1. Revise as configurações aplicadas"
        echo "2. Teste as conexões SSH antes de fechar a sessão atual"
        echo "3. Configure chaves SSH se ainda não o fez"
        echo "4. Monitore os logs em /var/log/"
        echo "5. Execute 'fail2ban-client status' para ver IPs bloqueados"
        
        if [[ "$SSH_PORT" != "22" ]]; then
            echo
            echo "ATENÇÃO: SSH agora está na porta $SSH_PORT!"
            echo "Use: ssh -p $SSH_PORT usuario@servidor"
        fi
    } >> "$REPORT_FILE"
    
    cat "$REPORT_FILE"
}

#-----------------------------------------------------------------------------
# Mostrar resumo final
#-----------------------------------------------------------------------------
show_summary() {
    echo
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         Hardening de Segurança Concluído! 🔒              ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    echo -e "${BLUE}Medidas de segurança aplicadas:${NC}"
    local count=0
    [[ "$ENABLE_UNATTENDED_UPGRADES" == "1" ]] && echo " $((++count)). Atualizações automáticas de segurança"
    [[ "$ENABLE_SSH_HARDENING" == "1" ]] && echo " $((++count)). SSH fortalecido"
    [[ "$ENABLE_FAIL2BAN" == "1" ]] && echo " $((++count)). Proteção contra brute force"
    [[ "$ENABLE_FIREWALL" == "1" ]] && echo " $((++count)). Firewall ativo"
    [[ "$ENABLE_KERNEL_HARDENING" == "1" ]] && echo " $((++count)). Kernel protegido"
    [[ "$ENABLE_AUDITD" == "1" ]] && echo " $((++count)). Auditoria de sistema"
    [[ "$ENABLE_APPARMOR" == "1" ]] && echo " $((++count)). Controle de acesso obrigatório"
    [[ "$ENABLE_ROOTKIT_HUNTER" == "1" ]] && echo " $((++count)). Detecção de rootkits"
    [[ "$ENABLE_AIDE" == "1" ]] && echo " $((++count)). Detecção de intrusão"
    [[ "$ENABLE_NETWORK_HARDENING" == "1" ]] && echo " $((++count)). Rede fortalecida"
    
    echo
    echo -e "${YELLOW}Próximos passos recomendados:${NC}"
    echo " 1. Configure chaves SSH para acesso sem senha"
    echo " 2. Revise os logs regularmente (/var/log/)"
    echo " 3. Mantenha o sistema atualizado"
    echo " 4. Faça backups regulares"
    echo " 5. Monitore tentativas de acesso não autorizado"
    
    echo
    echo -e "${GREEN}Relatórios salvos em:${NC}"
    echo " • Relatório inicial: $REPORT_FILE"
    echo " • Log de execução: $LOG_FILE"
    echo " • Backups: $BACKUP_DIR"
    
    if [[ "$SSH_PORT" != "22" ]]; then
        echo
        echo -e "${RED}⚠️  ATENÇÃO: SSH agora está na porta $SSH_PORT${NC}"
    fi
    
    echo
}

#-----------------------------------------------------------------------------
# Função principal
#-----------------------------------------------------------------------------
main() {
    clear
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          Security Hardening Script v2.0                    ║"
    echo "║         Fortalecimento de Segurança do Sistema            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Verificações iniciais
    check_system_requirements
    
    # Auditoria inicial
    security_audit
    
    # Aplicar medidas de segurança
    setup_unattended_upgrades
    harden_ssh
    setup_fail2ban
    setup_firewall
    harden_kernel
    setup_auditd
    setup_apparmor
    setup_rkhunter
    setup_aide
    harden_network
    
    # Limpeza e verificações finais
    final_cleanup
    
    # Gerar relatório
    generate_final_report
    
    # Verificação final
    if final_check; then
        show_summary
        info "Hardening concluído com sucesso!"
    else
        error "Alguns serviços não estão funcionando corretamente"
        error "Verifique os logs para mais detalhes"
        exit 1
    fi
}

# Executar função principal
main "$@"
