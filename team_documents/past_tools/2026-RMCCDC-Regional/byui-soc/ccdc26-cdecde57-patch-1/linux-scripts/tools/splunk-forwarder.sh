#!/bin/bash
# CCDC26 Linux Toolkit - Splunk Universal Forwarder Setup
# Forwards logs to the competition Splunk server (Oracle Linux 9.2, Splunk 10.0.2)
#
# Competition Splunk Server: 172.20.242.20:9997
# Run this on CLIENT machines (Ubuntu Ecom, Fedora Webmail, etc.) - NOT on the Splunk server

source "$(dirname "$0")/../utils/common.sh"
require_root

header "Splunk Universal Forwarder Setup"

# CONFIGURATION - Competition Splunk Server
SPLUNK_SERVER="172.20.242.20"
SPLUNK_PORT="9997"
SPLUNK_VERSION="10.2.0"
SPLUNK_BUILD="d749cb17ea65"
SPLUNK_HOME="/opt/splunkforwarder"
SPLUNK_USER="splunkfwd"

# Download URLs with build hash (verified working without authentication)
SPLUNK_DEB_URL="https://download.splunk.com/products/universalforwarder/releases/${SPLUNK_VERSION}/linux/splunkforwarder-${SPLUNK_VERSION}-${SPLUNK_BUILD}-linux-amd64.deb"
SPLUNK_RPM_URL="https://download.splunk.com/products/universalforwarder/releases/${SPLUNK_VERSION}/linux/splunkforwarder-${SPLUNK_VERSION}-${SPLUNK_BUILD}-linux-amd64.rpm"
SPLUNK_TGZ_URL="https://download.splunk.com/products/universalforwarder/releases/${SPLUNK_VERSION}/linux/splunkforwarder-${SPLUNK_VERSION}-${SPLUNK_BUILD}-linux-amd64.tgz"

check_installed() {
    if [[ -d "$SPLUNK_HOME" ]] && [[ -f "$SPLUNK_HOME/bin/splunk" ]]; then
        return 0
    fi
    return 1
}

install_forwarder() {
    info "Installing Splunk Universal Forwarder..."
    
    local tmp_dir="/tmp/splunk_install"
    mkdir -p "$tmp_dir"
    cd "$tmp_dir"
    
    case "$DISTRO_FAMILY" in
        debian)
            info "Downloading Splunk UF for Debian/Ubuntu..."
            if command -v wget &>/dev/null; then
                wget -q "$SPLUNK_DEB_URL" -O splunkforwarder.deb || {
                    warn "Download failed - trying manual install method"
                    manual_install
                    return
                }
            else
                curl -sL "$SPLUNK_DEB_URL" -o splunkforwarder.deb || {
                    warn "Download failed - trying manual install method"
                    manual_install
                    return
                }
            fi
            dpkg -i splunkforwarder.deb
            # Verify installation
            if [[ ! -f "$SPLUNK_HOME/bin/splunk" ]]; then
                error "Splunk binary not found after dpkg installation - installation failed"
                rm -rf "$tmp_dir"
                return 1
            fi
            ;;
        rhel)
            info "Downloading Splunk UF for RHEL/CentOS..."
            if command -v wget &>/dev/null; then
                wget -q "$SPLUNK_RPM_URL" -O splunkforwarder.rpm || {
                    warn "Download failed - trying manual install method"
                    manual_install
                    return
                }
            else
                curl -sL "$SPLUNK_RPM_URL" -o splunkforwarder.rpm || {
                    warn "Download failed - trying manual install method"
                    manual_install
                    return
                }
            fi
            rpm -i splunkforwarder.rpm
            # Verify installation
            if [[ ! -f "$SPLUNK_HOME/bin/splunk" ]]; then
                error "Splunk binary not found after rpm installation - installation failed"
                rm -rf "$tmp_dir"
                return 1
            fi
            ;;
        *)
            info "Downloading Splunk UF tarball..."
            manual_install
            return $?
            ;;
    esac
    
    rm -rf "$tmp_dir"
    success "Splunk Universal Forwarder installed"
}

manual_install() {
    info "Using tarball installation method..."
    local tmp_dir="/tmp/splunk_install"
    mkdir -p "$tmp_dir"
    cd "$tmp_dir"
    
    if command -v wget &>/dev/null; then
        wget -q "$SPLUNK_TGZ_URL" -O splunkforwarder.tgz || {
            error "Failed to download Splunk UF tarball"
            rm -rf "$tmp_dir"
            return 1
        }
    else
        curl -sL "$SPLUNK_TGZ_URL" -o splunkforwarder.tgz || {
            error "Failed to download Splunk UF tarball"
            rm -rf "$tmp_dir"
            return 1
        }
    fi
    
    if [[ -f splunkforwarder.tgz ]]; then
        tar -xzf splunkforwarder.tgz -C /opt/
        # Verify installation
        if [[ ! -f "$SPLUNK_HOME/bin/splunk" ]]; then
            error "Splunk binary not found after tarball extraction - installation failed"
            rm -rf "$tmp_dir"
            return 1
        fi
        success "Splunk UF extracted to /opt/splunkforwarder"
    else
        error "Failed to download Splunk UF"
        rm -rf "$tmp_dir"
        return 1
    fi
    
    rm -rf "$tmp_dir"
}

configure_forwarder() {
    info "Configuring Splunk forwarder to send to $SPLUNK_SERVER:$SPLUNK_PORT..."
    
    # Create local directory
    mkdir -p "$SPLUNK_HOME/etc/system/local"
    
    # Configure outputs.conf - where to send logs
    cat > "$SPLUNK_HOME/etc/system/local/outputs.conf" << EOF
[tcpout]
defaultGroup = competition_splunk

[tcpout:competition_splunk]
server = ${SPLUNK_SERVER}:${SPLUNK_PORT}
compressed = true

[tcpout-server://${SPLUNK_SERVER}:${SPLUNK_PORT}]
EOF

    # Configure inputs.conf - what logs to collect
    cat > "$SPLUNK_HOME/etc/system/local/inputs.conf" << EOF
# CCDC26 Splunk Forwarder - Log Collection
# Backup SIEM forwarding to competition Splunk server

[default]
host = $(hostname)

# =============================================================================
# SECURITY LOGS (Critical)
# =============================================================================
[monitor:///var/log/auth.log]
disabled = false
sourcetype = linux_secure
index = linux-security

[monitor:///var/log/secure]
disabled = false
sourcetype = linux_secure
index = linux-security

[monitor:///var/log/audit/audit.log]
disabled = false
sourcetype = linux_audit
index = linux-security

[monitor:///var/log/fail2ban.log]
disabled = false
sourcetype = fail2ban
index = linux-security

# =============================================================================
# SYSTEM LOGS
# =============================================================================
[monitor:///var/log/syslog]
disabled = false
sourcetype = syslog
index = linux-os

[monitor:///var/log/messages]
disabled = false
sourcetype = syslog
index = linux-os

[monitor:///var/log/kern.log]
disabled = false
sourcetype = linux_kernel
index = linux-os

[monitor:///var/log/cron*]
disabled = false
sourcetype = cron
index = linux-os

# =============================================================================
# WEB SERVER LOGS
# =============================================================================
[monitor:///var/log/apache2/*access*.log]
disabled = false
sourcetype = access_combined
index = linux-web

[monitor:///var/log/apache2/*error*.log]
disabled = false
sourcetype = apache_error
index = linux-web

[monitor:///var/log/httpd/*access*.log]
disabled = false
sourcetype = access_combined
index = linux-web

[monitor:///var/log/httpd/*error*.log]
disabled = false
sourcetype = apache_error
index = linux-web

[monitor:///var/log/nginx/access.log]
disabled = false
sourcetype = access_combined
index = linux-web

[monitor:///var/log/nginx/error.log]
disabled = false
sourcetype = nginx_error
index = linux-web

# =============================================================================
# DATABASE LOGS
# =============================================================================
[monitor:///var/log/mysql/*.log]
disabled = false
sourcetype = mysql_error
index = linux-database

[monitor:///var/log/mariadb/*.log]
disabled = false
sourcetype = mysql_error
index = linux-database

[monitor:///var/log/postgresql/*.log]
disabled = false
sourcetype = postgresql
index = linux-database

# =============================================================================
# MAIL LOGS
# =============================================================================
[monitor:///var/log/mail.log]
disabled = false
sourcetype = sendmail
index = linux-mail

[monitor:///var/log/maillog]
disabled = false
sourcetype = sendmail
index = linux-mail

# =============================================================================
# DNS LOGS
# =============================================================================
[monitor:///var/log/named/*.log]
disabled = false
sourcetype = named
index = linux-dns

[monitor:///var/log/bind/*.log]
disabled = false
sourcetype = named
index = linux-dns

# =============================================================================
# FTP LOGS
# =============================================================================
[monitor:///var/log/vsftpd.log]
disabled = false
sourcetype = vsftpd
index = linux-ftp

[monitor:///var/log/proftpd/*.log]
disabled = false
sourcetype = proftpd
index = linux-ftp
EOF

    # Set proper permissions
    chown -R root:root "$SPLUNK_HOME/etc/system/local"
    chmod 600 "$SPLUNK_HOME/etc/system/local"/*.conf
    
    success "Splunk forwarder configured"
}

start_forwarder() {
    info "Starting Splunk forwarder..."
    
    # Accept license and start
    "$SPLUNK_HOME/bin/splunk" start --accept-license --answer-yes --no-prompt 2>/dev/null
    
    # Enable boot start
    "$SPLUNK_HOME/bin/splunk" enable boot-start -systemd-managed 1 2>/dev/null || \
    "$SPLUNK_HOME/bin/splunk" enable boot-start 2>/dev/null
    
    success "Splunk forwarder started"
}

stop_forwarder() {
    info "Stopping Splunk forwarder..."
    "$SPLUNK_HOME/bin/splunk" stop 2>/dev/null
    success "Splunk forwarder stopped"
}

check_status() {
    header "Splunk Forwarder Status"
    
    if check_installed; then
        success "Splunk UF is installed at $SPLUNK_HOME"
        
        if "$SPLUNK_HOME/bin/splunk" status 2>/dev/null | grep -q "running"; then
            success "Splunk forwarder is running"
        else
            warn "Splunk forwarder is NOT running"
        fi
        
        info "Target server: $SPLUNK_SERVER:$SPLUNK_PORT"
        
        # Test connectivity
        if nc -zw3 "$SPLUNK_SERVER" "$SPLUNK_PORT" 2>/dev/null; then
            success "Connection to Splunk server: OK"
        else
            warn "Cannot connect to Splunk server on port $SPLUNK_PORT"
        fi
    else
        warn "Splunk UF is not installed"
    fi
}

test_forwarding() {
    info "Generating test event..."
    
    logger -t "SPLUNK_TEST" "CCDC26 Splunk forwarder test event - $(date)"
    
    success "Test event sent to syslog"
    info "Check Splunk server for events with sourcetype=syslog"
}

uninstall_forwarder() {
    warn "Uninstalling Splunk Universal Forwarder..."
    
    # Stop service
    "$SPLUNK_HOME/bin/splunk" stop 2>/dev/null
    
    # Disable boot start
    "$SPLUNK_HOME/bin/splunk" disable boot-start 2>/dev/null
    
    # Remove installation
    rm -rf "$SPLUNK_HOME"
    
    success "Splunk UF uninstalled"
}

quick_setup() {
    header "Quick Setup - Splunk Forwarder to $SPLUNK_SERVER"
    
    if check_installed; then
        info "Splunk UF already installed, reconfiguring..."
    else
        install_forwarder
    fi
    
    configure_forwarder
    start_forwarder
    check_status
    
    echo ""
    success "Splunk forwarder setup complete!"
    info "Logs are now being forwarded to $SPLUNK_SERVER:$SPLUNK_PORT"
}

show_menu() {
    echo ""
    echo "Splunk Universal Forwarder Setup"
    echo "================================="
    echo "Target Server: $SPLUNK_SERVER:$SPLUNK_PORT"
    echo ""
    echo "1) Quick Setup (install + configure + start)"
    echo "2) Install forwarder only"
    echo "3) Configure forwarder"
    echo "4) Start forwarder"
    echo "5) Stop forwarder"
    echo "6) Check status"
    echo "7) Test forwarding"
    echo "8) Uninstall"
    echo "9) Exit"
    echo ""
    read -p "Select option: " choice
    
    case $choice in
        1) quick_setup ;;
        2) install_forwarder ;;
        3) configure_forwarder ;;
        4) start_forwarder ;;
        5) stop_forwarder ;;
        6) check_status ;;
        7) test_forwarding ;;
        8) uninstall_forwarder ;;
        9) exit 0 ;;
        *) error "Invalid option" ;;
    esac
}

main() {
    if [[ $# -eq 0 ]]; then
        show_menu
    else
        case "$1" in
            quick|install) quick_setup ;;
            status) check_status ;;
            start) start_forwarder ;;
            stop) stop_forwarder ;;
            test) test_forwarding ;;
            *) show_menu ;;
        esac
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
