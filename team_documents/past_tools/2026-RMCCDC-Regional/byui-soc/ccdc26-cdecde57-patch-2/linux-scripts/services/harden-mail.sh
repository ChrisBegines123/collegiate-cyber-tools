#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Mail Server Hardening
# Secure Postfix, Dovecot, and related mail services

source "$(dirname "$0")/../utils/common.sh"
require_root

header "Mail Server Hardening"

#=============================================================================
# DETECT MAIL SERVICES
#=============================================================================
detect_mail_services() {
    MAIL_SERVICES=()
    
    systemctl is-active postfix &>/dev/null && MAIL_SERVICES+=("postfix")
    systemctl is-active dovecot &>/dev/null && MAIL_SERVICES+=("dovecot")
    systemctl is-active sendmail &>/dev/null && MAIL_SERVICES+=("sendmail")
    systemctl is-active exim4 &>/dev/null && MAIL_SERVICES+=("exim")
    
    if [ ${#MAIL_SERVICES[@]} -eq 0 ]; then
        warn "No running mail services detected"
        return 1
    fi
    
    info "Detected mail services: ${MAIL_SERVICES[*]}"
    return 0
}

#=============================================================================
# HARDEN POSTFIX
#=============================================================================
harden_postfix() {
    header "Hardening Postfix"
    
    if ! systemctl is-active postfix &>/dev/null; then
        error "Postfix is not running"
        return 1
    fi
    
    local main_cf="/etc/postfix/main.cf"
    backup_file "$main_cf"
    
    info "Updating Postfix configuration..."
    
    # Get hostname
    local myhostname=$(hostname -f 2>/dev/null || hostname)
    
    # Apply security settings using postconf
    postconf -e "smtpd_banner = \$myhostname ESMTP"
    postconf -e "biff = no"
    postconf -e "append_dot_mydomain = no"
    
    # Disable open relay but allow competition networks
    # CCDC NOTE: Scoring engine sends mail from external IPs!
    # Include the internal competition networks to allow scoring
    postconf -e "mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128 172.20.0.0/16 172.25.0.0/16 172.16.0.0/16 172.31.0.0/16"
    postconf -e "relay_domains ="
    info "NOTE: mynetworks includes competition subnets (172.x.x.x) for scoring"
    
    # SMTP restrictions
    postconf -e "smtpd_helo_required = yes"
    postconf -e "smtpd_helo_restrictions = permit_mynetworks, reject_non_fqdn_helo_hostname, reject_invalid_helo_hostname"
    postconf -e "smtpd_sender_restrictions = permit_mynetworks, reject_non_fqdn_sender, reject_unknown_sender_domain"
    postconf -e "smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination, reject_non_fqdn_recipient, reject_unknown_recipient_domain"
    
    # Rate limiting
    postconf -e "smtpd_client_connection_rate_limit = 30"
    postconf -e "smtpd_client_message_rate_limit = 30"
    postconf -e "smtpd_error_sleep_time = 5s"
    postconf -e "smtpd_soft_error_limit = 3"
    postconf -e "smtpd_hard_error_limit = 5"
    
    # Message size limit (25MB)
    postconf -e "message_size_limit = 26214400"
    
    # Disable VRFY and EXPN
    postconf -e "disable_vrfy_command = yes"
    
    # TLS settings (if certificates exist)
    if [ -f /etc/ssl/certs/ssl-cert-snakeoil.pem ]; then
        postconf -e "smtpd_tls_cert_file = /etc/ssl/certs/ssl-cert-snakeoil.pem"
        postconf -e "smtpd_tls_key_file = /etc/ssl/private/ssl-cert-snakeoil.key"
        postconf -e "smtpd_tls_security_level = may"
        postconf -e "smtpd_tls_auth_only = yes"
        postconf -e "smtpd_tls_loglevel = 1"
        postconf -e "smtpd_tls_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1"
        postconf -e "smtp_tls_security_level = may"
        postconf -e "smtp_tls_loglevel = 1"
    fi
    
    # Check for open relay
    info "Checking for open relay configuration..."
    local relay_domains=$(postconf -h relay_domains 2>/dev/null)
    if [ -n "$relay_domains" ] && [ "$relay_domains" != "\$mydestination" ]; then
        log_finding "Relay domains configured: $relay_domains"
    fi
    
    # Verify configuration
    if postfix check 2>/dev/null; then
        success "Postfix configuration valid"
        systemctl reload postfix
        success "Postfix reloaded"
    else
        error "Postfix configuration has errors!"
    fi
    
    log_action "Hardened Postfix"
}

#=============================================================================
# HARDEN DOVECOT
#=============================================================================
harden_dovecot() {
    header "Hardening Dovecot"
    
    if ! systemctl is-active dovecot &>/dev/null; then
        error "Dovecot is not running"
        return 1
    fi
    
    local dovecot_conf="/etc/dovecot/dovecot.conf"
    local local_conf="/etc/dovecot/conf.d/99-security.conf"
    
    # Create security config
    mkdir -p /etc/dovecot/conf.d
    
    cat > "$local_conf" << 'EOF'
# CCDC26 Dovecot Security Configuration

# Protocols
protocols = imap lmtp

# Listen addresses (localhost only by default)
# listen = 127.0.0.1, ::1

# SSL/TLS
# CCDC NOTE: Set to 'yes' instead of 'required' in case scoring uses plaintext
ssl = yes
ssl_min_protocol = TLSv1.2
ssl_cipher_list = ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384

# Disable plaintext auth except over SSL
disable_plaintext_auth = yes

# Authentication
auth_mechanisms = plain login

# Logging
log_path = /var/log/dovecot.log
auth_verbose = yes
auth_verbose_passwords = no
auth_debug = no

# Login settings
login_greeting = Mail Server Ready
login_log_format_elements = user=<%u> method=%m rip=%r lip=%l mpid=%e %c %k

# Mail location (adjust as needed)
# mail_location = maildir:~/Maildir

# Process limits
default_process_limit = 100
default_client_limit = 1000

# Brute force protection
auth_failure_delay = 2 secs
EOF

    # Check configuration
    if doveconf -n &>/dev/null; then
        success "Dovecot configuration valid"
        systemctl reload dovecot
        success "Dovecot reloaded"
    else
        error "Dovecot configuration has errors!"
        doveconf -n
    fi
    
    log_action "Hardened Dovecot"
}

#=============================================================================
# CHECK MAIL SECURITY
#=============================================================================
check_mail_security() {
    header "Checking Mail Server Security"
    
    # Check for open relay
    info "=== Open Relay Check ==="
    
    if systemctl is-active postfix &>/dev/null; then
        local mynetworks=$(postconf -h mynetworks 2>/dev/null)
        local relay_domains=$(postconf -h relay_domains 2>/dev/null)
        local smtpd_recipient=$(postconf -h smtpd_recipient_restrictions 2>/dev/null)
        
        echo "mynetworks: $mynetworks"
        echo "relay_domains: $relay_domains"
        echo "smtpd_recipient_restrictions: $smtpd_recipient"
        
        if [ -z "$smtpd_recipient" ] || ! echo "$smtpd_recipient" | grep -q "reject_unauth_destination"; then
            log_finding "Possible open relay - missing reject_unauth_destination"
        fi
    fi
    
    # Check listening ports
    info "=== Mail Ports ==="
    ss -tlnp | grep -E ':(25|465|587|110|143|993|995) '
    
    # Check mail queue
    info "=== Mail Queue ==="
    if command -v mailq &>/dev/null; then
        mailq | head -20
    fi
    
    # Check recent auth failures
    info "=== Recent Auth Failures ==="
    if [ -f /var/log/mail.log ]; then
        grep -i "auth.*fail\|login.*fail" /var/log/mail.log 2>/dev/null | tail -20
    fi
    
    # Check for suspicious senders
    info "=== Recent Mail Activity ==="
    if [ -f /var/log/mail.log ]; then
        grep "from=" /var/log/mail.log 2>/dev/null | tail -20
    fi
}

#=============================================================================
# AUDIT MAIL USERS
#=============================================================================
audit_mail_users() {
    header "Auditing Mail Users"
    
    # Check mail aliases
    info "=== Mail Aliases ==="
    if [ -f /etc/aliases ]; then
        grep -v "^#" /etc/aliases | grep -v "^$"
    fi
    
    # Check virtual users
    info "=== Virtual Users ==="
    for file in /etc/postfix/virtual /etc/postfix/vmailbox; do
        if [ -f "$file" ]; then
            info "Contents of $file:"
            cat "$file"
        fi
    done
    
    # Dovecot users
    if [ -f /etc/dovecot/users ]; then
        info "=== Dovecot Users ==="
        cat /etc/dovecot/users
    fi
    
    # Check SASL users
    if [ -d /etc/sasl2 ]; then
        info "=== SASL Configuration ==="
        cat /etc/sasl2/smtpd.conf 2>/dev/null
    fi
}

#=============================================================================
# FLUSH MAIL QUEUE
#=============================================================================
flush_mail_queue() {
    header "Managing Mail Queue"
    
    if ! command -v postqueue &>/dev/null; then
        error "Postfix not installed"
        return 1
    fi
    
    info "Current queue:"
    mailq | head -30
    
    local queue_count=$(mailq 2>/dev/null | tail -1 | grep -oE '[0-9]+' | head -1)
    
    echo ""
    echo "Options:"
    echo "1) Flush queue (attempt delivery)"
    echo "2) Delete all queued mail"
    echo "3) Delete mail from specific sender"
    echo "4) View queue details"
    echo ""
    read -p "Select option [1-4]: " choice
    
    case $choice in
        1)
            postqueue -f
            success "Queue flushed"
            ;;
        2)
            read -p "Delete ALL queued mail? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                postsuper -d ALL
                success "Queue cleared"
            fi
            ;;
        3)
            read -p "Enter sender address to delete: " sender
            mailq | grep "$sender" | awk '{print $1}' | tr -d '*!' | xargs -I {} postsuper -d {}
            success "Deleted mail from $sender"
            ;;
        4)
            read -p "Enter queue ID: " qid
            postcat -q "$qid"
            ;;
    esac
}

#=============================================================================
# TEST MAIL CONFIG
#=============================================================================
test_mail_config() {
    header "Testing Mail Configuration"
    
    # Test Postfix
    if systemctl is-active postfix &>/dev/null; then
        info "=== Postfix Configuration ==="
        postconf -n
        
        echo ""
        info "=== Testing SMTP ==="
        echo "QUIT" | nc -w 5 localhost 25 2>/dev/null || echo "Cannot connect to port 25"
    fi
    
    # Test Dovecot
    if systemctl is-active dovecot &>/dev/null; then
        info "=== Dovecot Configuration ==="
        doveconf -n | head -50
        
        echo ""
        info "=== Testing IMAP ==="
        echo "LOGOUT" | nc -w 5 localhost 143 2>/dev/null || echo "Cannot connect to port 143"
    fi
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    detect_mail_services
    
    echo ""
    echo "Mail Server Hardening Options:"
    echo "1) Harden Postfix"
    echo "2) Harden Dovecot"
    echo "3) Check mail security"
    echo "4) Audit mail users"
    echo "5) Manage mail queue"
    echo "6) Test mail configuration"
    echo "7) Harden all detected services"
    echo ""
    read -p "Select option [1-7]: " choice
    
    case $choice in
        1) harden_postfix ;;
        2) harden_dovecot ;;
        3) check_mail_security ;;
        4) audit_mail_users ;;
        5) flush_mail_queue ;;
        6) test_mail_config ;;
        7)
            for svc in "${MAIL_SERVICES[@]}"; do
                case "$svc" in
                    postfix) harden_postfix ;;
                    dovecot) harden_dovecot ;;
                esac
            done
            ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
