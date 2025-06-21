#!/usr/bin/env bash
###############################################################################
# Script: install_node_codex_codebuff.sh
# Descrição: instala Node.js LTS (20.x), @openai/codex CLI e Codebuff CLI
# Sistema-alvo: Ubuntu ≥ 20.04 (testado nos releases 22.04, 24.04, 25.04)
# Autor: philipe_cruz@outlook.com
###############################################################################

# Structured logging ----------------------------------------------------------
SCRIPT_NAME=$(basename "$0" .sh)
LOG_FILE="/var/log/${SCRIPT_NAME}.log"
mkdir -p "$(dirname "$LOG_FILE")" && touch "$LOG_FILE"
log()   { echo "$(date '+%F %T') [INFO] $*" | tee -a "$LOG_FILE"; }
warn()  { echo "$(date '+%F %T') [WARN] $*" | tee -a "$LOG_FILE"; }
err()   { echo "$(date '+%F %T') [FAIL] $*" | tee -a "$LOG_FILE"; exit 1; }

set -Eeuo pipefail
trap 'err "Linha $LINENO: comando \"$BASH_COMMAND\" falhou"' ERR

[[ $EUID -eq 0 ]] || err "Execute como root: sudo $0"

#######################################
# 1. Instala (ou atualiza) o Node.js #
#######################################
install_node() {
  if command -v node &>/dev/null; then
    CUR_V=$(node -v | sed 's/^v//')
    MAJOR=${CUR_V%%.*}
    if (( MAJOR >= 20 )); then
      info "Node.js $CUR_V já presente — pulando instalação"
      return
    fi
    warn "Node.js $CUR_V desatualizado, será atualizado para 20.x"
  else
    info "Node.js não encontrado, instalando 20.x via NodeSource…"
  fi

  # Repositório NodeSource
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y --no-install-recommends nodejs build-essential
  info "Node.js $(node -v) instalado"
}

##########################################
# 2. Instala @openai/codex e Codebuff CLI #
##########################################
install_cli_tools() {
  info "Atualizando npm globalmente…"
  npm install -g npm@latest >/dev/null

  # codex CLI
  if ! npm list -g --depth=0 | grep -q '@openai/codex'; then
    info "Instalando @openai/codex CLI…"
    npm install -g @openai/codex
  else
    info "@openai/codex já instalado — npm update"
    npm update -g @openai/codex
  fi

  # Codebuff CLI
  if ! npm list -g --depth=0 | grep -q 'codebuff@'; then
    info "Instalando Codebuff CLI…"
    npm install -g codebuff
  else
    info "Codebuff já instalado — npm update"
    npm update -g codebuff
  fi
}

############################################
# 3. Validação pós-instalação              #
############################################
verify() {
  echo
  info "Validação:"
  node -v  && npm -v
  echo -n "Codex  ➜ " && codex --version || true
  echo -n "Codebuff ➜ " && codebuff --version || true
  echo
  info "Instalação concluída. Use:"
  echo " • codex --help     # interagir com a Codex CLI"
  echo " • codebuff --help  # iniciar o agente Codebuff"
}

###########################
# Execução do script root #
###########################

apt-get update -qq
apt-get install -y curl ca-certificates >/dev/null

install_node
install_cli_tools
verify
