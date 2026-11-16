#!/bin/bash
# CCDC26 Linux Toolkit - Splunk Server Setup
# Configures the central Splunk server to receive forwarder data
#
# Run this on the Splunk SERVER (172.20.242.20), not the forwarders
#
# Usage:
#   ./splunk-server.sh              # Interactive menu
#   ./splunk-server.sh quick        # Quick setup (indexes + receiver)
#   ./splunk-server.sh indexes      # Create indexes only

source "$(dirname "$0")/../utils/common.sh" 2>/dev/null || {
    # Fallback if common.sh not available
    info() { echo "[INFO] $*"; }
    success() { echo "[OK] $*"; }
    warn() { echo "[WARN] $*"; }
    error() { echo "[ERROR] $*"; }
    header() { echo ""; echo "=== $* ==="; }
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
    exit 1
fi

header "Splunk Server Setup"

# CONFIGURATION - Competition Environment (Oracle Linux 9.2, Splunk 10.0.2)
# Server IP: 172.20.242.20
# System creds: root:changemenow, sysadmin:changemenow
SPLUNK_HOME="${SPLUNK_HOME:-/opt/splunk}"
SPLUNK_PORT="9997"  # Receiving port for forwarders
SPLUNK_ADMIN="${SPLUNK_ADMIN:-admin}"
SPLUNK_PASSWORD="${SPLUNK_PASSWORD:-changeme}"  # Default competition password

# Indexes that match inputs.conf on forwarders
# Linux indexes
LINUX_INDEXES=(
    "linux-security"   # auth.log, secure, audit.log, fail2ban
    "linux-os"         # syslog, messages, kern.log, cron
    "linux-web"        # apache, httpd, nginx logs
    "linux-database"   # mysql, mariadb, postgresql logs
    "linux-mail"       # mail.log, maillog
    "linux-dns"        # named, bind logs
    "linux-ftp"        # vsftpd, proftpd logs
)

# Windows indexes (granular)
WINDOWS_INDEXES=(
    "windows-security"     # Security EventLog
    "windows-system"       # System EventLog
    "windows-application"  # Application EventLog
    "windows-powershell"   # PowerShell logs
    "windows-sysmon"       # Sysmon operational logs
    "windows-dns"          # DNS Server EventLog
)

# Combined for iteration
INDEXES=("${LINUX_INDEXES[@]}" "${WINDOWS_INDEXES[@]}")

# Get admin credentials (uses defaults or prompts)
get_credentials() {
    # Use environment variables or defaults
    if [[ -z "$SPLUNK_ADMIN" ]]; then
        SPLUNK_ADMIN="admin"
    fi
    
    if [[ -z "$SPLUNK_PASSWORD" ]]; then
        SPLUNK_PASSWORD="changeme"
    fi
    
    info "Using Splunk credentials: $SPLUNK_ADMIN"
    
    # Option to override if needed
    read -p "Use default credentials? [Y/n]: " use_default
    if [[ "$use_default" =~ ^[Nn] ]]; then
        read -p "Splunk admin username [$SPLUNK_ADMIN]: " new_admin
        SPLUNK_ADMIN="${new_admin:-$SPLUNK_ADMIN}"
        read -sp "Splunk admin password: " SPLUNK_PASSWORD
        echo ""
    fi
    
    if [[ -z "$SPLUNK_PASSWORD" ]]; then
        error "Password cannot be empty"
        exit 1
    fi
}

# Verify Splunk is installed and running
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

# Create all required indexes
create_indexes() {
    header "Creating Indexes"
    
    local auth_arg="-auth ${SPLUNK_ADMIN}:${SPLUNK_PASSWORD}"
    
    for idx in "${INDEXES[@]}"; do
        info "Creating index: $idx"
        
        # Check if index already exists
        if "$SPLUNK_HOME/bin/splunk" list index $auth_arg 2>/dev/null | grep -q "^$idx$"; then
            info "  Index '$idx' already exists, skipping"
        else
            "$SPLUNK_HOME/bin/splunk" add index "$idx" $auth_arg 2>/dev/null
            if [[ $? -eq 0 ]]; then
                success "  Created index: $idx"
            else
                warn "  Failed to create index: $idx (may already exist)"
            fi
        fi
    done
    
    echo ""
    info "Index summary:"
    "$SPLUNK_HOME/bin/splunk" list index $auth_arg 2>/dev/null | grep -E "^(linux-|windows-)" | while read idx; do
        echo "  - $idx"
    done
}

# Enable receiving port for forwarders
enable_receiver() {
    header "Enabling Receiver Port"
    
    local auth_arg="-auth ${SPLUNK_ADMIN}:${SPLUNK_PASSWORD}"
    
    info "Enabling TCP input on port $SPLUNK_PORT..."
    
    # Check if already enabled
    if "$SPLUNK_HOME/bin/splunk" list tcp $auth_arg 2>/dev/null | grep -q ":$SPLUNK_PORT"; then
        info "Receiver port $SPLUNK_PORT already enabled"
    else
        "$SPLUNK_HOME/bin/splunk" enable listen $SPLUNK_PORT $auth_arg
        if [[ $? -eq 0 ]]; then
            success "Receiver enabled on port $SPLUNK_PORT"
        else
            error "Failed to enable receiver port"
        fi
    fi
    
    # Verify port is listening
    if ss -tlnp 2>/dev/null | grep -q ":$SPLUNK_PORT" || netstat -tlnp 2>/dev/null | grep -q ":$SPLUNK_PORT"; then
        success "Port $SPLUNK_PORT is listening"
    else
        warn "Port $SPLUNK_PORT may not be listening yet - Splunk restart may be needed"
    fi
}

# Configure firewall if needed
configure_firewall() {
    header "Firewall Configuration"
    
    # Check for common firewalls
    if command -v firewall-cmd &>/dev/null; then
        info "Configuring firewalld..."
        firewall-cmd --permanent --add-port=${SPLUNK_PORT}/tcp 2>/dev/null
        firewall-cmd --permanent --add-port=8000/tcp 2>/dev/null  # Web UI
        firewall-cmd --permanent --add-port=8089/tcp 2>/dev/null  # Management
        firewall-cmd --reload 2>/dev/null
        success "Firewalld rules added"
    elif command -v ufw &>/dev/null; then
        info "Configuring ufw..."
        ufw allow ${SPLUNK_PORT}/tcp 2>/dev/null
        ufw allow 8000/tcp 2>/dev/null  # Web UI
        ufw allow 8089/tcp 2>/dev/null  # Management
        success "UFW rules added"
    elif command -v iptables &>/dev/null; then
        info "Configuring iptables..."
        iptables -A INPUT -p tcp --dport $SPLUNK_PORT -j ACCEPT 2>/dev/null
        iptables -A INPUT -p tcp --dport 8000 -j ACCEPT 2>/dev/null
        iptables -A INPUT -p tcp --dport 8089 -j ACCEPT 2>/dev/null
        success "iptables rules added (not persisted)"
        warn "Run 'iptables-save' to persist rules"
    else
        warn "No firewall detected - ensure ports $SPLUNK_PORT, 8000, 8089 are open"
    fi
}

# Show status
show_status() {
    header "Splunk Server Status"
    
    local auth_arg="-auth ${SPLUNK_ADMIN}:${SPLUNK_PASSWORD}"
    
    echo ""
    echo "Splunk Home: $SPLUNK_HOME"
    echo ""
    
    # Service status
    if "$SPLUNK_HOME/bin/splunk" status 2>/dev/null | grep -q "splunkd is running"; then
        success "Splunk service: Running"
    else
        error "Splunk service: NOT running"
    fi
    
    # Receiver port
    if ss -tlnp 2>/dev/null | grep -q ":$SPLUNK_PORT" || netstat -tlnp 2>/dev/null | grep -q ":$SPLUNK_PORT"; then
        success "Receiver port $SPLUNK_PORT: Listening"
    else
        warn "Receiver port $SPLUNK_PORT: NOT listening"
    fi
    
    # Web UI
    if ss -tlnp 2>/dev/null | grep -q ":8000" || netstat -tlnp 2>/dev/null | grep -q ":8000"; then
        success "Web UI port 8000: Listening"
    else
        warn "Web UI port 8000: NOT listening"
    fi
    
    echo ""
    info "Configured indexes:"
    "$SPLUNK_HOME/bin/splunk" list index $auth_arg 2>/dev/null | grep -E "^(linux-|windows-)" | while read idx; do
        echo "  - $idx"
    done
    
    echo ""
    info "Connected forwarders:"
    "$SPLUNK_HOME/bin/splunk" list forward-server $auth_arg 2>/dev/null || echo "  (none or unable to list)"
}

# Quick setup - do everything
quick_setup() {
    header "Quick Setup - Splunk Server"
    
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

# Interactive menu
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
    read -p "Select option: " choice
    
    case $choice in
        1) 
            quick_setup 
            ;;
        2) 
            get_credentials
            check_splunk
            create_indexes 
            ;;
        3) 
            get_credentials
            check_splunk
            enable_receiver 
            ;;
        4) 
            configure_firewall 
            ;;
        5) 
            get_credentials
            show_status 
            ;;
        6)
            info "Restarting Splunk..."
            "$SPLUNK_HOME/bin/splunk" restart
            ;;
        7) 
            exit 0 
            ;;
        *) 
            error "Invalid option" 
            ;;
    esac
}

# Main
main() {
    if [[ $# -eq 0 ]]; then
        show_menu
    else
        case "$1" in
            quick|setup)
                quick_setup
                ;;
            indexes)
                get_credentials
                check_splunk
                create_indexes
                ;;
            receiver)
                get_credentials
                check_splunk
                enable_receiver
                ;;
            firewall)
                configure_firewall
                ;;
            status)
                get_credentials
                show_status
                ;;
            *)
                echo "Usage: $0 [quick|indexes|receiver|firewall|status]"
                exit 1
                ;;
        esac
    fi
}

main "$@"
