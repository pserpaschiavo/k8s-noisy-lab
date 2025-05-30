#!/bin/bash

# Cores para output
export GREEN='\033[0;32m'
export RED='\033[0;31m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export NO_COLOR='\033[0m'

# Variável global para o arquivo de log
LOG_FILE=""

# Função para inicializar o logger
init_logger() {
    local log_file="$1"
    LOG_FILE="$log_file"
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
}

# Função de log
log() {
    local color="$1" message="$2"
    printf "%b%s%b\n" "$color" "$message" "$NO_COLOR"
    # Only write to log file if LOG_FILE is set
    if [ -n "$LOG_FILE" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
    fi
}

# Funções específicas de log
log_info() {
    log "$BLUE" "[INFO] $1"
}

log_success() {
    log "$GREEN" "[SUCCESS] $1"
}

log_warning() {
    log "$YELLOW" "[WARNING] $1"
}

log_error() {
    log "$RED" "[ERROR] $1"
}
