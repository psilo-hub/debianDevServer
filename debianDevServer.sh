#!/usr/bin/env bash
set -euo pipefail

SCRIPT_VERSION="1.0.0"

# Determine the invoking user and their home directory
if [[ -n "${SUDO_USER:-}" ]]; then
    ORIGINAL_USER="$SUDO_USER"
    ORIGINAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6 || echo "/home/$SUDO_USER")
else
    ORIGINAL_USER=$(id -un 2>/dev/null || echo "root")
    ORIGINAL_HOME="${HOME:-/root}"
fi

# ─── ANSI Colors ─────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Helper Functions ────────────────────────────────────────────────────────

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; }
header(){ echo -e "\n${BOLD}${MAGENTA}━━━ $* ━━━${NC}\n"; }

run() {
    echo -e "${CYAN}[RUN]${NC} $*"
    "$@"
}

# ─── Interactive Helpers ──────────────────────────────────────────────────────

ask_yes_no() {
    local prompt="$1"
    local default="${2:-Y}"
    local reply
    while true; do
        echo -ne "${CYAN}[?]${NC}  $prompt "
        read -r reply
        case "$reply" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            "") [[ "$default" == "Y" ]] && return 0 || return 1 ;;
            *) warn "Please answer y or n." ;;
        esac
    done
}

interactive_prompt() {
    if [[ ! -t 0 ]]; then
        info "Non-interactive mode detected — installing default components"
        RUN_BASE_TOOLS=true
        RUN_NODE=true
        RUN_JAVA=true
        RUN_MAVEN=true
        RUN_OPENCODE=true
        RUN_TELEGRAM_BOT=true
        RUN_CODE_SERVER=true
        RUN_UTILS=true
        RUN_DOTFILES=true
        return
    fi
    header "Component selection"
    echo -e "Choose which components to install. ${BOLD}[Y/n]${NC} defaults to Yes."
    echo
    ask_yes_no "Install base tools (build-essential, curl, git, htop, tmux)?" && RUN_BASE_TOOLS=true || RUN_BASE_TOOLS=false
    RUN_NODE=true
    ask_yes_no "Install Java?" && RUN_JAVA=true || RUN_JAVA=false
    ask_yes_no "Install Maven?" && RUN_MAVEN=true || RUN_MAVEN=false
    ask_yes_no "Install opencode CLI?" && RUN_OPENCODE=true || RUN_OPENCODE=false
    ask_yes_no "Install opencode Telegram bot?" && RUN_TELEGRAM_BOT=true || RUN_TELEGRAM_BOT=false
    ask_yes_no "Install VS Code Server?" && RUN_CODE_SERVER=true || RUN_CODE_SERVER=false
    ask_yes_no "Install utilities (ripgrep, fd-find, bat, jq, shellcheck, tree, ncdu)?" && RUN_UTILS=true || RUN_UTILS=false
    ask_yes_no "Install dotfiles (.bashrc additions, .gitconfig, .tmux.conf, .inputrc)?" && RUN_DOTFILES=true || RUN_DOTFILES=false
}

should_run() {
    local section="$1"
    local varname="RUN_${section^^}"
    [[ "${!varname}" == "true" ]]
}

# ─── Auto-elevation ──────────────────────────────────────────────────────────

if [[ $EUID -ne 0 ]]; then
    if [[ -t 0 ]]; then
        echo -e "${BLUE}[INFO]${NC}  Re-executing with sudo..."
        exec sudo bash "$0"
    else
        echo -e "${RED}[FAIL]${NC}  This script must be run as root when piped."
        echo "       Use: curl -fsSL <url> | sudo bash"
        exit 1
    fi
fi

# ─── Installation Functions ──────────────────────────────────────────────────

check_debian() {
    header "Checking system"
    if [[ ! -f /etc/os-release ]]; then
        fail "Not a Debian-based system (missing /etc/os-release)"
        exit 1
    fi
    . /etc/os-release
    if [[ "${ID:-}" != "debian" ]]; then
        warn "This script is designed for Debian (ID=${ID:-unknown})"
    fi
    ok "Running on ${NAME} ${VERSION_ID}"
}

update_system() {
    header "Updating system packages"
    export DEBIAN_FRONTEND=noninteractive
    run apt-get upgrade -y
}

install_base_tools() {
    header "Installing base tools"
    local pkgs=()
    for pkg in build-essential curl git htop tmux; do
        dpkg -s "$pkg" &>/dev/null || pkgs+=("$pkg")
    done
    if [[ ${#pkgs[@]} -gt 0 ]]; then
        run apt-get install -y "${pkgs[@]}"
    else
        ok "Base tools already installed"
    fi
}

install_node() {
    header "Installing Node.js 22.x"
    if command -v node &>/dev/null; then
        ok "Node.js already installed ($(node --version 2>/dev/null || echo 'unknown'))"
        return
    fi
    run curl -fsSL https://deb.nodesource.com/setup_22.x -o /tmp/nodesetup.sh
    run bash /tmp/nodesetup.sh
    run apt-get install -y nodejs
    local node_ver
    node_ver=$(node --version 2>/dev/null || echo "unknown")
    ok "Node.js ${node_ver} installed"
}

install_java() {
    header "Installing Java"
    if command -v java &>/dev/null; then
        ok "Java already installed ($(java --version 2>&1 | head -1))"
        return
    fi
    if [[ -z "${DISPLAY:-}" ]]; then
        run apt-get install -y default-jdk-headless
    else
        run apt-get install -y default-jdk
    fi
    ok "Java installed"
}

install_maven() {
    header "Installing Maven"
    if command -v mvn &>/dev/null; then
        ok "Maven already installed ($(mvn --version 2>&1 | head -1))"
        return
    fi
    run apt-get install -y maven
    ok "Maven installed"
}

install_opencode() {
    header "Installing opencode CLI"
    if command -v opencode &>/dev/null; then
        ok "opencode already installed"
        return
    fi
    run bash -c 'curl -fsSL https://opencode.ai/install | bash'
    ok "opencode installed"
}

install_telegram_bot() {
    header "Installing opencode Telegram bot"
    # Ensure Node.js is installed since the Telegram bot requires npm
    if ! command -v node &>/dev/null; then
        info "Node.js is required for opencode Telegram bot - installing Node.js 22.x"
        install_node
    fi
    if command -v opencode-telegram-bot &>/dev/null; then
        ok "opencode Telegram bot already installed"
        return
    fi
    run npm install -g @grinev/opencode-telegram-bot
    ok "opencode Telegram bot installed"
}

install_code_server() {
    header "Installing VS Code Server"
    if command -v code-server &>/dev/null; then
        ok "code-server already installed"
        return
    fi
    run bash -c 'curl -fsSL https://code-server.dev/install.sh | sh'
    ok "code-server installed"
    configure_code_server_password
}

configure_code_server_password() {
    local config_dir="${ORIGINAL_HOME}/.config/code-server"
    local config_file="${config_dir}/config.yaml"
    if command -v openssl &>/dev/null; then
        CODER_PASSWORD=$(openssl rand -base64 12)
    else
        CODER_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom 2>/dev/null | head -c 16 || echo "changeme123")
    fi
    mkdir -p "$config_dir"
    cat > "$config_file" <<- EOF
bind-addr: 0.0.0.0:8080
auth: password
password: ${CODER_PASSWORD}
cert: false
EOF
    ok "code-server password configured"
}

install_utils() {
    header "Installing utilities"
    local pkgs=()
    for pkg in ripgrep fd-find bat jq shellcheck tree ncdu; do
        dpkg -s "$pkg" &>/dev/null || pkgs+=("$pkg")
    done
    if [[ ${#pkgs[@]} -gt 0 ]]; then
        run apt-get install -y "${pkgs[@]}"
    else
        ok "Utilities already installed"
    fi
}

install_firewall() {
    header "Configuring firewall"
    if ! dpkg -s ufw &>/dev/null; then
        run apt-get install -y ufw
    fi
    run ufw --force reset
    run ufw default deny incoming
    run ufw default allow outgoing
    run ufw allow ssh
    run ufw allow 8080/tcp comment 'code-server'
    run ufw --force enable
    ok "Firewall enabled (SSH 22, code-server 8080)"
}

install_dotfiles() {
    header "Installing dotfiles"
    local home="$ORIGINAL_HOME"
    # .bashrc additions
    local bashrc_d="${home}/.bashrc.d"
    mkdir -p "$bashrc_d"
    local bashrc_file="${bashrc_d}/debianDevServer"
    if [[ ! -f "$bashrc_file" ]]; then
        cat > "$bashrc_file" <<- 'EOF'
# debianDevServer additions
export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
EOF
        ok "bash aliases written to ${bashrc_file}"
    fi
    local bashrc="${home}/.bashrc"
    if [[ -f "$bashrc" ]] && ! grep -q "bashrc.d/debianDevServer" "$bashrc"; then
        echo -e "\n# Source debianDevServer additions\nfor f in ~/.bashrc.d/*; do source \"\$f\"; done" >> "$bashrc"
        ok ".bashrc updated to source additions"
    fi
    # .gitconfig
    if [[ ! -f "${home}/.gitconfig" ]]; then
        cat > "${home}/.gitconfig" <<- 'EOF'
[alias]
    co = checkout
    br = branch
    st = status
    ci = commit
    lg = log --oneline --graph --all --decorate
EOF
        ok ".gitconfig created"
    fi
    # .tmux.conf
    if [[ ! -f "${home}/.tmux.conf" ]]; then
        cat > "${home}/.tmux.conf" <<- 'EOF'
set -g prefix C-a
unbind C-b
bind C-a send-prefix
set -g base-index 1
set -g pane-base-index 1
set -g history-limit 10000
EOF
        ok ".tmux.conf created"
    fi
    # .inputrc
    if [[ ! -f "${home}/.inputrc" ]]; then
        cat > "${home}/.inputrc" <<- 'EOF'
set completion-ignore-case on
set show-all-if-ambiguous on
"\e[A": history-search-backward
"\e[B": history-search-forward
EOF
        ok ".inputrc created"
    fi
}

print_summary() {
    header "Installation complete"
    echo -e "${BOLD}Summary:${NC}"
    echo -e "  ${GREEN}✓${NC} System updated"
    echo -e "  ${GREEN}✓${NC} Base tools installed"
    echo -e "  ${GREEN}✓${NC} Node.js installed"
    echo -e "  ${GREEN}✓${NC} Java installed"
    echo -e "  ${GREEN}✓${NC} Maven installed"
    echo -e "  ${GREEN}✓${NC} opencode CLI installed"
    echo -e "  ${GREEN}✓${NC} opencode Telegram bot installed"
    echo -e "  ${GREEN}✓${NC} VS Code Server installed"
    echo -e "  ${GREEN}✓${NC} Utilities installed"
    echo -e "  ${GREEN}✓${NC} Firewall configured and enabled"
    echo -e "  ${GREEN}✓${NC} Dotfiles installed"
    echo
    if [[ -n "${CODER_PASSWORD:-}" ]]; then
        echo -e "${BOLD}${YELLOW}  ⚠  code-server password: ${CODER_PASSWORD}${NC}"
        echo -e "      Save this password — it will not be shown again."
        echo
    fi
    echo -e "${BOLD}Open ports:${NC} 22 (SSH), 8080 (code-server)"
    echo -e "${BOLD}Reboot recommended${NC} to ensure all services start properly."
}

main() {
    echo -e "${BOLD}${MAGENTA}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║       debianDevServer v${SCRIPT_VERSION}             ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${NC}"

    interactive_prompt
    check_debian
    update_system
    should_run "base_tools"   && install_base_tools
    should_run "node"         && install_node
    should_run "java"         && install_java
    should_run "maven"        && install_maven
    should_run "opencode"     && install_opencode
    should_run "telegram_bot" && install_telegram_bot
    should_run "code_server"  && install_code_server
    should_run "utils"        && install_utils
    # Firewall is mandatory - always runs
    install_firewall
    should_run "dotfiles"     && install_dotfiles
    print_summary
}

main
