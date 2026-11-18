#!/bin/bash
# CCDC26 Splunk Server Setup (self-contained)
# Configures the central Splunk server to receive forwarder data
#
# Run this on the Splunk SERVER, not the forwarders.
#
# Usage:
#   ./server-setup.sh              # Interactive menu
#   ./server-setup.sh quick        # Quick setup (indexes + receiver)
#   ./server-setup.sh indexes      # Create indexes only

#=============================================================================
# COLORS AND OUTPUT (inlined — no external dependency)
#=============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
header()  { echo -e "\n${BOLD}${PURPLE}=== $* ===${NC}\n"; }

if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
    exit 1
fi

header "Splunk Server Setup"

SPLUNK_HOME="${SPLUNK_HOME:-/opt/splunk}"
SPLUNK_PORT="9997"
SPLUNK_ADMIN="${SPLUNK_ADMIN:-admin}"
SPLUNK_PASSWORD="${SPLUNK_PASSWORD:-changeme}"

LINUX_INDEXES=(
    "linux-security"
    "linux-os"
    "linux-web"
    "linux-database"
    "linux-mail"
    "linux-dns"
    "linux-ftp"
)

WINDOWS_INDEXES=(
    "windows-security"
    "windows-system"
    "windows-application"
    "windows-powershell"
    "windows-sysmon"
    "windows-dns"
)

INDEXES=("${LINUX_INDEXES[@]}" "${WINDOWS_INDEXES[@]}")

get_credentials() {
    if [[ -z "$SPLUNK_ADMIN" ]]; then
        SPLUNK_ADMIN="admin"
    fi
    if [[ -z "$SPLUNK_PASSWORD" ]]; then
        SPLUNK_PASSWORD="changeme"
    fi

    info "Using Splunk credentials: $SPLUNK_ADMIN"

    read -rp "Use default credentials? [Y/n]: " use_default
    if [[ "$use_default" =~ ^[Nn] ]]; then
        read -rp "Splunk admin username [$SPLUNK_ADMIN]: " new_admin
        SPLUNK_ADMIN="${new_admin:-$SPLUNK_ADMIN}"
        read -rsp "Splunk admin password: " SPLUNK_PASSWORD
        echo ""
    fi

    if [[ -z "$SPLUNK_PASSWORD" ]]; then
        error "Password cannot be empty"
        exit 1
    fi
}

check_splunk() {
    if [[ ! -f "$SPLUNK_HOME/bin/splunk" ]]; then
        error "Splunk not found at $SPLUNK_HOME"
        error "Set SPLUNK_HOME environment variable if installed elsewhere"
        exit 1
    fi

    if ! "$SPLUNK_HOME/bin/splunk" status 2>/dev/null | grep -q "splunkd is running"; then
        warn "Splunk is not running. Starting..."
        "$SPLUNK_HOME/bin/splunk" start --accept-license --answer-yes --no-prompt
        sleep 5
    fi

    success "Splunk is running"
}

create_indexes() {
    header "Creating Indexes"

    local auth_arg="-auth ${SPLUNK_ADMIN}:${SPLUNK_PASSWORD}"

    for idx in "${INDEXES[@]}"; do
        info "Creating index: $idx"
        if "$SPLUNK_HOME/bin/splunk" list index $auth_arg 2>/dev/null | grep -q "^$idx$"; then
            info "  Index '$idx' already exists, skipping"
        else
            if "$SPLUNK_HOME/bin/splunk" add index "$idx" $auth_arg 2>/dev/null; then
                success "  Created index: $idx"
            else
                warn "  Failed to create index: $idx (may already exist)"
            fi
        fi
    done

    echo ""
    info "Index summary:"
    "$SPLUNK_HOME/bin/splunk" list index $auth_arg 2>/dev/null | grep -E "^(linux-|windows-)" | while read -r idx; do
        echo "  - $idx"
    done
}

enable_receiver() {
    header "Enabling Receiver Port"

    local auth_arg="-auth ${SPLUNK_ADMIN}:${SPLUNK_PASSWORD}"

    info "Enabling TCP input on port $SPLUNK_PORT..."

    if "$SPLUNK_HOME/bin/splunk" list tcp $auth_arg 2>/dev/null | grep -q ":$SPLUNK_PORT"; then
        info "Receiver port $SPLUNK_PORT already enabled"
    else
        if "$SPLUNK_HOME/bin/splunk" enable listen $SPLUNK_PORT $auth_arg; then
            success "Receiver enabled on port $SPLUNK_PORT"
        else
            error "Failed to enable receiver port"
        fi
    fi

    if ss -tlnp 2>/dev/null | grep -q ":$SPLUNK_PORT" || netstat -tlnp 2>/dev/null | grep -q ":$SPLUNK_PORT"; then
        success "Port $SPLUNK_PORT is listening"
    else
        warn "Port $SPLUNK_PORT may not be listening yet — Splunk restart may be needed"
    fi
}

configure_firewall() {
    header "Firewall Configuration"

    if command -v firewall-cmd &>/dev/null; then
        info "Configuring firewalld..."
        firewall-cmd --permanent --add-port=${SPLUNK_PORT}/tcp 2>/dev/null
        firewall-cmd --permanent --add-port=8000/tcp 2>/dev/null
        firewall-cmd --permanent --add-port=8089/tcp 2>/dev/null
        firewall-cmd --reload 2>/dev/null
        success "Firewalld rules added"
    elif command -v ufw &>/dev/null; then
        info "Configuring ufw..."
        ufw allow ${SPLUNK_PORT}/tcp 2>/dev/null
        ufw allow 8000/tcp 2>/dev/null
        ufw allow 8089/tcp 2>/dev/null
        success "UFW rules added"
    elif command -v iptables &>/dev/null; then
        info "Configuring iptables..."
        iptables -A INPUT -p tcp --dport $SPLUNK_PORT -j ACCEPT 2>/dev/null
        iptables -A INPUT -p tcp --dport 8000 -j ACCEPT 2>/dev/null
        iptables -A INPUT -p tcp --dport 8089 -j ACCEPT 2>/dev/null
        success "iptables rules added (not persisted)"
        warn "Run 'iptables-save' to persist rules"
    else
        warn "No firewall detected — ensure ports $SPLUNK_PORT, 8000, 8089 are open"
    fi
}

show_status() {
    header "Splunk Server Status"

    local auth_arg="-auth ${SPLUNK_ADMIN}:${SPLUNK_PASSWORD}"

    echo ""
    echo "Splunk Home: $SPLUNK_HOME"
    echo ""

    if "$SPLUNK_HOME/bin/splunk" status 2>/dev/null | grep -q "splunkd is running"; then
        success "Splunk service: Running"
    else
        error "Splunk service: NOT running"
    fi

    if ss -tlnp 2>/dev/null | grep -q ":$SPLUNK_PORT" || netstat -tlnp 2>/dev/null | grep -q ":$SPLUNK_PORT"; then
        success "Receiver port $SPLUNK_PORT: Listening"
    else
        warn "Receiver port $SPLUNK_PORT: NOT listening"
    fi

    if ss -tlnp 2>/dev/null | grep -q ":8000" || netstat -tlnp 2>/dev/null | grep -q ":8000"; then
        success "Web UI port 8000: Listening"
    else
        warn "Web UI port 8000: NOT listening"
    fi

    echo ""
    info "Configured indexes:"
    "$SPLUNK_HOME/bin/splunk" list index $auth_arg 2>/dev/null | grep -E "^(linux-|windows-)" | while read -r idx; do
        echo "  - $idx"
    done

    echo ""
    info "Connected forwarders:"
    "$SPLUNK_HOME/bin/splunk" list forward-server $auth_arg 2>/dev/null || echo "  (none or unable to list)"
}

quick_setup() {
    header "Quick Setup — Splunk Server"

    get_credentials
    check_splunk
    create_indexes
    enable_receiver
    configure_firewall

    echo ""
    echo "=========================================="
    success "Splunk server setup complete!"
    echo "=========================================="
    echo ""
    echo "Receiver port: $SPLUNK_PORT"
    echo "Web UI: https://$(hostname -I | awk '{print $1}'):8000"
    echo ""
    echo "Indexes created:"
    for idx in "${INDEXES[@]}"; do
        echo "  - $idx"
    done
    echo ""
    echo "Forwarders can now send data to this server."
    echo "=========================================="
}

show_menu() {
    echo ""
    echo "Splunk Server Setup"
    echo "==================="
    echo "SPLUNK_HOME: $SPLUNK_HOME"
    echo ""
    echo "1) Quick Setup (indexes + receiver + firewall)"
    echo "2) Create indexes only"
    echo "3) Enable receiver port only"
    echo "4) Configure firewall only"
    echo "5) Show status"
    echo "6) Restart Splunk"
    echo "7) Exit"
    echo ""
    read -rp "Select option: " choice

    case $choice in
        1) quick_setup ;;
        2) get_credentials; check_splunk; create_indexes ;;
        3) get_credentials; check_splunk; enable_receiver ;;
        4) configure_firewall ;;
        5) get_credentials; show_status ;;
        6) info "Restarting Splunk..."; "$SPLUNK_HOME/bin/splunk" restart ;;
        7) exit 0 ;;
        *) error "Invalid option" ;;
    esac
}

# Main
if [[ $# -eq 0 ]]; then
    show_menu
else
    case "$1" in
        quick|setup) quick_setup ;;
        indexes)     get_credentials; check_splunk; create_indexes ;;
        receiver)    get_credentials; check_splunk; enable_receiver ;;
        firewall)    configure_firewall ;;
        status)      get_credentials; show_status ;;
        *)           echo "Usage: $0 [quick|indexes|receiver|firewall|status]"; exit 1 ;;
    esac
fi
