#!/usr/bin/env bash
###############################################################################
# Script: install_node_codex_codebuff.sh
# Descrição: instala Node.js LTS (20.x), @openai/codex CLI e Codebuff CLI
# Sistema-alvo: Ubuntu ≥ 20.04 (testado nos releases 22.04, 24.04, 25.04)
# Autor: philipe_cruz@outlook.com
###############################################################################
set -Eeuo pipefail
trap 'echo -e "\e[31m[ERRO]\e[0m Linha $LINENO: comando \"$BASH_COMMAND\" falhou"; exit 1' ERR

log()   { echo -e "\e[32m[INFO]\e[0m $*"; }
warn()  { echo -e "\e[33m[WARN]\e[0m $*"; }
err()   { echo -e "\e[31m[FAIL]\e[0m $*"; exit 1; }

#######################################
# 1. Instala (ou atualiza) o Node.js #
#######################################
install_node() {
  if command -v node &>/dev/null; then
    CUR_V=$(node -v | sed 's/^v//')
    MAJOR=${CUR_V%%.*}
    if (( MAJOR >= 20 )); then
      log "Node.js $CUR_V já presente — pulando instalação"
      return
    fi
    warn "Node.js $CUR_V desatualizado, será atualizado para 20.x"
  else
    log "Node.js não encontrado, instalando 20.x via NodeSource…"
  fi

  # Repositório NodeSource
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y --no-install-recommends nodejs build-essential
  log "Node.js $(node -v) instalado"
}

##########################################
# 2. Instala @openai/codex e Codebuff CLI #
##########################################
install_cli_tools() {
  log "Atualizando npm globalmente…"
  npm install -g npm@latest >/dev/null

  # codex CLI
  if ! npm list -g --depth=0 | grep -q '@openai/codex'; then
    log "Instalando @openai/codex CLI…"
    npm install -g @openai/codex
  else
    log "@openai/codex já instalado — npm update"
    npm update -g @openai/codex
  fi

  # Codebuff CLI
  if ! npm list -g --depth=0 | grep -q 'codebuff@'; then
    log "Instalando Codebuff CLI…"
    npm install -g codebuff
  else
    log "Codebuff já instalado — npm update"
    npm update -g codebuff
  fi
}

############################################
# 3. Validação pós-instalação              #
############################################
verify() {
  echo
  log "Validação:"
  node -v  && npm -v
  echo -n "Codex  ➜ " && codex --version || true
  echo -n "Codebuff ➜ " && codebuff --version || true
  echo
  log "Instalação concluída. Use:"
  echo " • codex --help     # interagir com a Codex CLI"
  echo " • codebuff --help  # iniciar o agente Codebuff"
}

###########################
# Execução do script root #
###########################
[[ $EUID -eq 0 ]] || err "Execute como root: sudo $0"

apt-get update -qq
apt-get install -y curl ca-certificates >/dev/null

install_node
install_cli_tools
verify
