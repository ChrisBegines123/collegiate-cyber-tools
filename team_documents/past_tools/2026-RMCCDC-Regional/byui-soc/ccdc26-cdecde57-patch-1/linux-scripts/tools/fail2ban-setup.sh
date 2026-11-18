#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Fail2ban Setup
# Install and configure fail2ban for intrusion prevention

source "$(dirname "$0")/../utils/common.sh"
require_root

header "Fail2ban Setup"

#=============================================================================
# INSTALL FAIL2BAN
#=============================================================================
install_fail2ban() {
    header "Installing Fail2ban"
    
    if command -v fail2ban-client &>/dev/null; then
        success "Fail2ban is already installed"
        fail2ban-client --version
        return 0
    fi
    
    info "Installing fail2ban..."
    case "$PKG_MGR" in
        apt)
            apt-get update
            apt-get install -y fail2ban
            ;;
        dnf|yum)
            $PKG_MGR install -y epel-release 2>/dev/null
            $PKG_MGR install -y fail2ban
            ;;
        apk)
            apk add fail2ban
            ;;
        pacman)
            pacman -S --noconfirm fail2ban
            ;;
        zypper)
            zypper install -y fail2ban
            ;;
    esac
    
    if command -v fail2ban-client &>/dev/null; then
        success "Fail2ban installed successfully"
    else
        error "Failed to install fail2ban"
        return 1
    fi
}

#=============================================================================
# CONFIGURE FAIL2BAN
#=============================================================================
configure_fail2ban() {
    header "Configuring Fail2ban"
    
    # Backup existing config
    backup_file /etc/fail2ban/jail.local
    
    # Create comprehensive jail.local
    cat > /etc/fail2ban/jail.local << 'EOF'
# CCDC26 Fail2ban Configuration
# Aggressive settings for competition

[DEFAULT]
# Ban settings
bantime = 3600
findtime = 600
maxretry = 3
banaction = iptables-multiport
backend = auto

# Email notifications (configure if needed)
# destemail = admin@localhost
# sender = fail2ban@localhost
# mta = sendmail
# action = %(action_mwl)s

# Ignore localhost
ignoreip = 127.0.0.1/8 ::1

#=============================================================================
# SSH Protection
#=============================================================================
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = %(sshd_log)s
maxretry = 3
bantime = 3600

[sshd-ddos]
enabled = true
port = ssh
filter = sshd-ddos
logpath = %(sshd_log)s
maxretry = 5
bantime = 3600

#=============================================================================
# Web Server Protection
#=============================================================================
[apache-auth]
enabled = true
port = http,https
filter = apache-auth
logpath = %(apache_error_log)s
maxretry = 3

[apache-badbots]
enabled = true
port = http,https
filter = apache-badbots
logpath = %(apache_access_log)s
maxretry = 1
bantime = 86400

[apache-noscript]
enabled = true
port = http,https
filter = apache-noscript
logpath = %(apache_error_log)s
maxretry = 3

[apache-overflows]
enabled = true
port = http,https
filter = apache-overflows
logpath = %(apache_error_log)s
maxretry = 2

[apache-shellshock]
enabled = true
port = http,https
filter = apache-shellshock
logpath = %(apache_error_log)s
maxretry = 1
bantime = 86400

[nginx-http-auth]
enabled = true
port = http,https
filter = nginx-http-auth
logpath = /var/log/nginx/error.log
maxretry = 3

[nginx-botsearch]
enabled = true
port = http,https
filter = nginx-botsearch
logpath = /var/log/nginx/access.log
maxretry = 2

[nginx-badbots]
enabled = true
port = http,https
filter = apache-badbots
logpath = /var/log/nginx/access.log
maxretry = 1
bantime = 86400

#=============================================================================
# Database Protection
#=============================================================================
[mysqld-auth]
enabled = true
port = 3306
filter = mysqld-auth
logpath = /var/log/mysql/error.log
maxretry = 3

[postgres]
enabled = true
port = 5432
filter = postgres
logpath = /var/log/postgresql/postgresql-*-main.log
maxretry = 3

#=============================================================================
# Mail Server Protection
#=============================================================================
[postfix]
enabled = true
port = smtp,465,submission
filter = postfix
logpath = /var/log/mail.log
maxretry = 3

[postfix-sasl]
enabled = true
port = smtp,465,submission,imap,imaps,pop3,pop3s
filter = postfix-sasl
logpath = /var/log/mail.log
maxretry = 3

[dovecot]
enabled = true
port = pop3,pop3s,imap,imaps,submission,465,sieve
filter = dovecot
logpath = %(dovecot_log)s
maxretry = 3

#=============================================================================
# FTP Protection
#=============================================================================
[vsftpd]
enabled = true
port = ftp,ftp-data,ftps,ftps-data
filter = vsftpd
logpath = /var/log/vsftpd.log
maxretry = 3

[proftpd]
enabled = true
port = ftp,ftp-data,ftps,ftps-data
filter = proftpd
logpath = /var/log/proftpd/proftpd.log
maxretry = 3

[pure-ftpd]
enabled = true
port = ftp,ftp-data,ftps,ftps-data
filter = pure-ftpd
logpath = /var/log/syslog
maxretry = 3

#=============================================================================
# DNS Protection
#=============================================================================
[named-refused]
enabled = true
port = domain,953
filter = named-refused
logpath = /var/log/named/security.log
maxretry = 3

#=============================================================================
# Generic Protection
#=============================================================================
[recidive]
enabled = true
filter = recidive
logpath = /var/log/fail2ban.log
action = iptables-allports[name=recidive]
bantime = 604800
findtime = 86400
maxretry = 3

[pam-generic]
enabled = true
filter = pam-generic
port = all
logpath = %(syslog_authpriv)s
maxretry = 3
EOF

    success "Fail2ban configured"
    log_action "Configured fail2ban"
}

#=============================================================================
# CREATE CUSTOM FILTERS
#=============================================================================
create_custom_filters() {
    header "Creating Custom Filters"
    
    # Web shell detection filter
    cat > /etc/fail2ban/filter.d/webshell.conf << 'EOF'
# Detect web shell access attempts
[Definition]
failregex = ^<HOST> .* "(GET|POST).*(cmd=|exec=|shell=|passthru=|system=|eval\().*"
            ^<HOST> .* "(GET|POST).*(\.php\?.*=http|\.asp\?.*=http).*"
            ^<HOST> .* "(GET|POST).*(c99|r57|b374k|weevely|wso).*"
ignoreregex =
EOF

    # SQL injection detection filter
    cat > /etc/fail2ban/filter.d/sqli.conf << 'EOF'
# Detect SQL injection attempts
[Definition]
failregex = ^<HOST> .* "(GET|POST).*(union.*select|select.*from|insert.*into|delete.*from|drop.*table|update.*set).*"
            ^<HOST> .* "(GET|POST).*(\/\*|\*\/|@@|char\(|concat\().*"
            ^<HOST> .* "(GET|POST).*(benchmark\(|sleep\(|load_file\().*"
ignoreregex =
EOF

    # Path traversal detection filter
    cat > /etc/fail2ban/filter.d/traversal.conf << 'EOF'
# Detect path traversal attempts
[Definition]
failregex = ^<HOST> .* "(GET|POST).*(\.\.\/|\.\.\\|%2e%2e%2f|%252e%252e%252f).*"
            ^<HOST> .* "(GET|POST).*(\/etc\/passwd|\/etc\/shadow|win\.ini|boot\.ini).*"
ignoreregex =
EOF

    # Add custom jails for these filters
    cat >> /etc/fail2ban/jail.local << 'EOF'

#=============================================================================
# Custom Security Filters
#=============================================================================
[webshell]
enabled = true
port = http,https
filter = webshell
logpath = /var/log/apache2/access.log
          /var/log/nginx/access.log
          /var/log/httpd/access_log
maxretry = 1
bantime = 86400

[sqli]
enabled = true
port = http,https
filter = sqli
logpath = /var/log/apache2/access.log
          /var/log/nginx/access.log
          /var/log/httpd/access_log
maxretry = 2
bantime = 86400

[traversal]
enabled = true
port = http,https
filter = traversal
logpath = /var/log/apache2/access.log
          /var/log/nginx/access.log
          /var/log/httpd/access_log
maxretry = 2
bantime = 86400
EOF

    success "Custom filters created"
}

#=============================================================================
# START FAIL2BAN
#=============================================================================
start_fail2ban() {
    header "Starting Fail2ban"
    
    # Enable and start service
    service_start fail2ban
    
    sleep 2
    
    # Check status
    if fail2ban-client status &>/dev/null; then
        success "Fail2ban is running"
        fail2ban-client status
    else
        error "Fail2ban failed to start"
        journalctl -u fail2ban -n 20 --no-pager
    fi
}

#=============================================================================
# SHOW STATUS
#=============================================================================
show_status() {
    header "Fail2ban Status"
    
    if ! command -v fail2ban-client &>/dev/null; then
        error "Fail2ban is not installed"
        return 1
    fi
    
    info "Service status:"
    fail2ban-client status
    
    echo ""
    info "Active jails:"
    for jail in $(fail2ban-client status | grep "Jail list" | cut -d: -f2 | tr ',' ' '); do
        jail=$(echo "$jail" | tr -d ' \t')
        [ -z "$jail" ] && continue
        echo ""
        warn "=== $jail ==="
        fail2ban-client status "$jail"
    done
}

#=============================================================================
# UNBAN IP
#=============================================================================
unban_ip() {
    header "Unban IP Address"
    
    read -p "Enter IP to unban: " ip
    read -p "Enter jail name (or 'all' for all jails): " jail
    
    if [ -z "$ip" ]; then
        error "No IP provided"
        return
    fi
    
    if [ "$jail" == "all" ]; then
        for j in $(fail2ban-client status | grep "Jail list" | cut -d: -f2 | tr ',' ' '); do
            j=$(echo "$j" | tr -d ' \t')
            [ -z "$j" ] && continue
            fail2ban-client set "$j" unbanip "$ip" 2>/dev/null
        done
        success "Unbanned $ip from all jails"
    else
        fail2ban-client set "$jail" unbanip "$ip"
        success "Unbanned $ip from $jail"
    fi
    
    log_action "Unbanned IP: $ip"
}

#=============================================================================
# BAN IP MANUALLY
#=============================================================================
ban_ip() {
    header "Manually Ban IP"
    
    read -p "Enter IP to ban: " ip
    read -p "Enter jail name: " jail
    
    if [ -z "$ip" ] || [ -z "$jail" ]; then
        error "IP and jail required"
        return
    fi
    
    fail2ban-client set "$jail" banip "$ip"
    success "Banned $ip in $jail"
    log_action "Manually banned IP: $ip in $jail"
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    echo ""
    echo "Fail2ban Options:"
    echo "1) Install fail2ban"
    echo "2) Configure fail2ban"
    echo "3) Create custom filters"
    echo "4) Start/restart fail2ban"
    echo "5) Show status"
    echo "6) Unban IP"
    echo "7) Manually ban IP"
    echo "8) Full setup (install + configure + start)"
    echo ""
    read -p "Select option [1-8]: " choice
    
    case $choice in
        1) install_fail2ban ;;
        2) configure_fail2ban ;;
        3) create_custom_filters ;;
        4) start_fail2ban ;;
        5) show_status ;;
        6) unban_ip ;;
        7) ban_ip ;;
        8)
            install_fail2ban
            configure_fail2ban
            create_custom_filters
            start_fail2ban
            show_status
            ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
