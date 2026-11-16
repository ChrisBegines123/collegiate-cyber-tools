#!/bin/bash
# CCDC26 Defense Toolkit -- Linux Entry Point
# Usage:
#   sudo ./deploy.sh              # Interactive: configure + launch Monarch
#   sudo ./deploy.sh --quick      # Non-interactive: run 01-harden.sh locally
#   sudo ./deploy.sh --monarch    # Jump straight to Monarch REPL
#   sudo ./deploy.sh --configure  # Edit config.env only
#   sudo ./deploy.sh --serve      # HTTP server for Windows deployment
#   sudo ./deploy.sh --help       # Show help

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source environment config
if [ -f "$SCRIPT_DIR/config.env" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/config.env"
fi

#=============================================================================
# COLORS AND OUTPUT
#=============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
header()  { echo -e "\n${BOLD}${PURPLE}=== $1 ===${NC}\n"; }

#=============================================================================
# BANNER
#=============================================================================
show_banner() {
    echo -e "${CYAN}"
    echo "  ██████╗ ██████╗██████╗  ██████╗██████╗  ██████╗ "
    echo " ██╔════╝██╔════╝██╔══██╗██╔════╝╚════██╗██╔════╝ "
    echo " ██║     ██║     ██║  ██║██║      █████╔╝███████╗ "
    echo " ██║     ██║     ██║  ██║██║     ██╔═══╝ ██╔═══██╗"
    echo " ╚██████╗╚██████╗██████╔╝╚██████╗███████╗╚██████╔╝"
    echo "  ╚═════╝ ╚═════╝╚═════╝  ╚═════╝╚══════╝ ╚═════╝ "
    echo -e "${NC}"
    echo -e "${BOLD}CCDC26 Defense Toolkit${NC}  —  Monarch Workflow"
    echo ""
}

#=============================================================================
# ROOT CHECK
#=============================================================================
require_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Must be root. Run: sudo $0"
        exit 1
    fi
}

#=============================================================================
# INSTALL DEPENDENCIES
#=============================================================================
install_deps() {
    header "Installing Dependencies"

    local pkgs=(git python3 python3-pip sshpass)

    if command -v apt-get &>/dev/null; then
        apt-get update -qq
        apt-get install -y -qq "${pkgs[@]}" 2>/dev/null
    elif command -v dnf &>/dev/null; then
        dnf install -y -q "${pkgs[@]}" 2>/dev/null
    elif command -v yum &>/dev/null; then
        yum install -y -q "${pkgs[@]}" 2>/dev/null
    else
        warn "Unknown package manager — install manually: ${pkgs[*]}"
    fi

    pip3 install -q paramiko python-dotenv 2>/dev/null
    success "Dependencies installed"
}

#=============================================================================
# GENERATE config.ps1 FROM config.env
#=============================================================================
generate_ps_config() {
    local src="$SCRIPT_DIR/config.env"
    local dst="$SCRIPT_DIR/config.ps1"

    if [ ! -f "$src" ]; then
        error "config.env not found"
        return 1
    fi

    info "Generating config.ps1 from config.env ..."

    # Build the hashtable entries by reading exports from config.env
    local entries=""
    while IFS= read -r line; do
        # Match lines like: export VAR_NAME="value"  or  export VAR_NAME=value
        if [[ "$line" =~ ^export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)=[\""]?([^\"]*)[\""]?$ ]]; then
            local bash_name="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Convert UPPER_SNAKE_CASE to PascalCase
            local pascal=""
            IFS='_' read -ra parts <<< "$bash_name"
            for part in "${parts[@]}"; do
                pascal+="$(echo "${part:0:1}" | tr '[:lower:]' '[:upper:]')$(echo "${part:1}" | tr '[:upper:]' '[:lower:]')"
            done

            # Pad key for alignment
            local padded
            padded=$(printf "%-20s" "$pascal")
            local escaped="${value//\`/\`\`}"
            escaped="${escaped//\"/\`\"}"
            entries+="    ${padded}= \"${escaped}\"\n"
        fi
    done < "$src"

    cat > "$dst" << 'HEADER'
# CCDC Environment Configuration - PowerShell
# =============================================
# AUTO-GENERATED from config.env — re-run ./deploy.sh --configure to refresh.
# Do not edit by hand; edit config.env instead.

# BEGIN CONFIG
$script:EnvConfig = @{
HEADER

    echo -e "$entries" >> "$dst"

    cat >> "$dst" << 'FOOTER'
}

$script:EnvConfigured = $true
# END CONFIG

function Get-EnvConfig {
    return $script:EnvConfig
}

function Test-EnvConfigured {
    if (-not $script:EnvConfigured) {
        Write-Host ""
        Write-Host "[!!] Environment is NOT configured." -ForegroundColor Red
        Write-Host "     Run deploy.sh --configure on the Linux box to regenerate." -ForegroundColor Red
        Write-Host ""
        return $false
    }
    return $true
}
FOOTER

    success "config.ps1 generated"
}

#=============================================================================
# CONFIGURE
#=============================================================================
configure() {
    header "Configure Environment"

    local editor="${EDITOR:-vi}"
    info "Opening config.env in $editor ..."
    "$editor" "$SCRIPT_DIR/config.env"

    # Re-source after editing
    source "$SCRIPT_DIR/config.env"

    if [ "$CONFIGURED" = "true" ]; then
        success "config.env loaded (CONFIGURED=true)"
        generate_ps_config
    else
        warn "CONFIGURED is not true — set CONFIGURED=\"true\" in config.env when ready."
    fi
}

#=============================================================================
# QUICK HARDEN (this machine only)
#=============================================================================
quick_harden() {
    require_root
    header "Quick Harden — This Machine Only"

    if [ -f "$SCRIPT_DIR/monarch/scripts/01-harden.sh" ]; then
        info "Running 01-harden.sh ..."
        bash "$SCRIPT_DIR/monarch/scripts/01-harden.sh"
    else
        error "monarch/scripts/01-harden.sh not found — cannot harden"
        return 1
    fi

    if [ -f "$SCRIPT_DIR/monarch/scripts/02-firewall.sh" ]; then
        info "Running 02-firewall.sh ..."
        bash "$SCRIPT_DIR/monarch/scripts/02-firewall.sh"
    else
        error "monarch/scripts/02-firewall.sh not found — cannot apply firewall"
        return 1
    fi

    success "Quick harden complete"
}

#=============================================================================
# LAUNCH MONARCH
#=============================================================================
launch_monarch() {
    require_root

    if [ ! -d "$SCRIPT_DIR/monarch" ]; then
        error "monarch/ directory not found"
        exit 1
    fi

    if [ ! -f "$SCRIPT_DIR/monarch/run.sh" ]; then
        error "monarch/run.sh not found"
        exit 1
    fi

    install_deps

    header "Launching Monarch"
    cd "$SCRIPT_DIR/monarch" || exit 1
    exec ./run.sh
}

#=============================================================================
# SERVE TOOLKIT (HTTP server for Windows deployment)
#=============================================================================
serve_toolkit() {
    header "Serving Toolkit via HTTP"

    local port=8080
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    ip="${ip:-<THIS_IP>}"

    echo ""
    info "Starting HTTP server on port $port ..."
    echo ""
    echo -e "  ${BOLD}Windows machines can download the toolkit from:${NC}"
    echo -e "    ${GREEN}http://${ip}:${port}/deploy.ps1${NC}"
    echo -e "    ${GREEN}http://${ip}:${port}/config.ps1${NC}"
    echo ""
    echo -e "  ${YELLOW}On Windows (PowerShell as Admin):${NC}"
    echo -e "    iwr http://${ip}:${port}/deploy.ps1 -OutFile C:\\deploy.ps1"
    echo -e "    iwr http://${ip}:${port}/config.ps1 -OutFile C:\\config.ps1"
    echo ""
    echo -e "  Press ${BOLD}Ctrl+C${NC} to stop."
    echo ""

    cd "$SCRIPT_DIR" || exit 1
    python3 -m http.server "$port"
}

#=============================================================================
# HELP
#=============================================================================
show_help() {
    show_banner
    echo "Usage: sudo $0 [option]"
    echo ""
    echo "OPTIONS:"
    echo "  (none)        Interactive menu"
    echo "  --quick       Harden THIS machine (01-harden + 02-firewall)"
    echo "  --monarch     Jump straight to Monarch REPL"
    echo "  --configure   Edit config.env, regenerate config.ps1"
    echo "  --serve       HTTP server so Windows can pull deploy.ps1"
    echo "  --help        Show this help"
    echo ""
    echo "TYPICAL WORKFLOW:"
    echo "  1. sudo ./deploy.sh --configure    # fill in IPs"
    echo "  2. sudo ./deploy.sh --quick        # harden this box"
    echo "  3. sudo ./deploy.sh --monarch      # manage all Linux"
    echo "  4. sudo ./deploy.sh --serve        # let Windows pull scripts"
    echo ""
}

#=============================================================================
# MAIN MENU
#=============================================================================
main_menu() {
    if [ "$CONFIGURED" != "true" ]; then
        warn "config.env is not configured yet."
        read -rp "Open config.env in editor now? (Y/n): " yn
        if [ "$yn" != "n" ] && [ "$yn" != "N" ]; then
            configure
        fi
    fi

    while true; do
        show_banner

        echo -e "  ${BOLD}1)${NC} Quick Harden          (this machine only)"
        echo -e "  ${BOLD}2)${NC} Launch Monarch         (manage all Linux machines)"
        echo -e "  ${BOLD}3)${NC} Serve toolkit          (HTTP server for Windows)"
        echo -e "  ${BOLD}4)${NC} Configure environment  (edit config.env)"
        echo -e "  ${BOLD}q)${NC} Quit"
        echo ""
        read -rp "Select option: " choice

        case $choice in
            1) quick_harden ;;
            2) launch_monarch ;;
            3) serve_toolkit ;;
            4) configure ;;
            q|Q) echo "Goodbye!"; exit 0 ;;
            *) error "Invalid option" ;;
        esac

        echo ""
        read -rp "Press Enter to continue..."
        clear
    done
}

#=============================================================================
# CLI DISPATCH
#=============================================================================
case "${1:-}" in
    --quick|-q)     require_root; quick_harden ;;
    --monarch|-m)   require_root; launch_monarch ;;
    --configure|-c) configure ;;
    --serve|-s)     serve_toolkit ;;
    --help|-h)      show_help; exit 0 ;;
    "")             require_root; main_menu ;;
    *)              error "Unknown option: $1"; show_help; exit 1 ;;
esac
