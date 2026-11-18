#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Universal Service Hardening
# Auto-detect and harden all running services

source "$(dirname "$0")/../utils/common.sh"
require_root

SCRIPT_DIR="$(dirname "$0")"

header "Universal Service Hardening"

#=============================================================================
# DETECT ALL SERVICES
#=============================================================================
detect_all_services() {
    header "Detecting Running Services"
    
    DETECTED_SERVICES=()
    
    # Web servers
    if systemctl is-active apache2 &>/dev/null || systemctl is-active httpd &>/dev/null; then
        DETECTED_SERVICES+=("apache")
        info "Found: Apache"
    fi
    
    if systemctl is-active nginx &>/dev/null; then
        DETECTED_SERVICES+=("nginx")
        info "Found: Nginx"
    fi
    
    # Databases
    if systemctl is-active mysql &>/dev/null || systemctl is-active mariadb &>/dev/null; then
        DETECTED_SERVICES+=("mysql")
        info "Found: MySQL/MariaDB"
    fi
    
    if systemctl is-active postgresql &>/dev/null; then
        DETECTED_SERVICES+=("postgresql")
        info "Found: PostgreSQL"
    fi
    
    # Mail
    if systemctl is-active postfix &>/dev/null; then
        DETECTED_SERVICES+=("postfix")
        info "Found: Postfix"
    fi
    
    if systemctl is-active dovecot &>/dev/null; then
        DETECTED_SERVICES+=("dovecot")
        info "Found: Dovecot"
    fi
    
    # FTP
    if systemctl is-active vsftpd &>/dev/null; then
        DETECTED_SERVICES+=("vsftpd")
        info "Found: vsftpd"
    fi
    
    if systemctl is-active proftpd &>/dev/null; then
        DETECTED_SERVICES+=("proftpd")
        info "Found: ProFTPD"
    fi
    
    # DNS
    if systemctl is-active named &>/dev/null || systemctl is-active bind9 &>/dev/null; then
        DETECTED_SERVICES+=("bind")
        info "Found: BIND/named"
    fi
    
    # SSH
    if systemctl is-active sshd &>/dev/null || systemctl is-active ssh &>/dev/null; then
        DETECTED_SERVICES+=("ssh")
        info "Found: SSH"
    fi
    
    # Samba
    if systemctl is-active smbd &>/dev/null; then
        DETECTED_SERVICES+=("samba")
        info "Found: Samba"
    fi
    
    # LDAP
    if systemctl is-active slapd &>/dev/null; then
        DETECTED_SERVICES+=("ldap")
        info "Found: OpenLDAP"
    fi
    
    echo ""
    info "Total services detected: ${#DETECTED_SERVICES[@]}"
}

#=============================================================================
# SHOW SERVICE STATUS
#=============================================================================
show_service_status() {
    header "Service Status Overview"
    
    printf "%-20s %-10s %-10s %s\n" "SERVICE" "STATUS" "PORT" "NOTES"
    printf "%-20s %-10s %-10s %s\n" "-------" "------" "----" "-----"
    
    # Check common services
    local services=(
        "sshd:22:SSH"
        "apache2:80:Web"
        "httpd:80:Web"
        "nginx:80:Web"
        "mysql:3306:Database"
        "mariadb:3306:Database"
        "postgresql:5432:Database"
        "postfix:25:Mail"
        "dovecot:143:Mail"
        "vsftpd:21:FTP"
        "proftpd:21:FTP"
        "named:53:DNS"
        "bind9:53:DNS"
        "smbd:445:Samba"
        "slapd:389:LDAP"
    )
    
    for entry in "${services[@]}"; do
        IFS=: read -r svc port desc <<< "$entry"
        
        local status="stopped"
        systemctl is-active "$svc" &>/dev/null && status="RUNNING"
        
        if [ "$status" == "RUNNING" ]; then
            local listening=$(ss -tlnp | grep ":$port " | head -1)
            printf "${GREEN}%-20s %-10s %-10s %s${NC}\n" "$svc" "$status" "$port" "$desc"
        fi
    done
}

#=============================================================================
# HARDEN ALL SERVICES
#=============================================================================
harden_all_services() {
    header "Hardening All Detected Services"
    
    for service in "${DETECTED_SERVICES[@]}"; do
        echo ""
        case "$service" in
            apache|nginx)
                info "Hardening web server..."
                bash "$SCRIPT_DIR/harden-webserver.sh" <<< "7"
                ;;
            mysql|postgresql)
                info "Hardening database..."
                bash "$SCRIPT_DIR/harden-database.sh" <<< "7"
                ;;
            postfix|dovecot)
                info "Hardening mail server..."
                bash "$SCRIPT_DIR/harden-mail.sh" <<< "7"
                ;;
            vsftpd|proftpd)
                info "Hardening FTP server..."
                bash "$SCRIPT_DIR/harden-ftp.sh" <<< "7"
                ;;
            bind)
                info "Hardening DNS server..."
                bash "$SCRIPT_DIR/harden-dns.sh" <<< "1"
                ;;
            ssh)
                info "SSH hardening handled by main toolkit"
                ;;
        esac
    done
    
    success "All services hardened"
    log_action "Hardened all detected services"
}

#=============================================================================
# QUICK SECURITY CHECK
#=============================================================================
quick_security_check() {
    header "Quick Security Check"
    
    # Check listening ports
    info "=== Open Ports ==="
    ss -tlnp | grep LISTEN
    
    echo ""
    info "=== Established Connections ==="
    ss -tnp | grep ESTAB | head -20
    
    echo ""
    info "=== World-Writable Service Dirs ==="
    for dir in /var/www /srv /var/lib/mysql /var/lib/postgresql; do
        [ -d "$dir" ] && find "$dir" -type d -perm -0002 2>/dev/null | head -5
    done
    
    echo ""
    info "=== Service Accounts with Shells ==="
    awk -F: '($3 < 1000) && ($7 !~ /nologin|false/) && ($7 != "") {print $1": "$7}' /etc/passwd
}

#=============================================================================
# BACKUP ALL CONFIGS
#=============================================================================
backup_all_configs() {
    header "Backing Up Service Configurations"
    
    local backup_dir="/root/service-configs-$(timestamp)"
    mkdir -p "$backup_dir"
    
    # Copy configurations
    cp -r /etc/apache2 "$backup_dir/" 2>/dev/null
    cp -r /etc/httpd "$backup_dir/" 2>/dev/null
    cp -r /etc/nginx "$backup_dir/" 2>/dev/null
    cp -r /etc/mysql "$backup_dir/" 2>/dev/null
    cp -r /etc/postgresql* "$backup_dir/" 2>/dev/null
    cp -r /etc/postfix "$backup_dir/" 2>/dev/null
    cp -r /etc/dovecot "$backup_dir/" 2>/dev/null
    cp /etc/vsftpd.conf "$backup_dir/" 2>/dev/null
    cp -r /etc/vsftpd "$backup_dir/" 2>/dev/null
    cp -r /etc/proftpd "$backup_dir/" 2>/dev/null
    cp -r /etc/bind "$backup_dir/" 2>/dev/null
    cp /etc/named.conf "$backup_dir/" 2>/dev/null
    cp -r /etc/ssh "$backup_dir/" 2>/dev/null
    
    # Create tarball
    tar -czf "${backup_dir}.tar.gz" -C /root "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    success "Configurations backed up to: ${backup_dir}.tar.gz"
    log_action "Backed up all service configurations"
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    detect_all_services
    
    echo ""
    echo "Universal Service Hardening Options:"
    echo "1) Show service status"
    echo "2) Harden web servers"
    echo "3) Harden databases"
    echo "4) Harden mail servers"
    echo "5) Harden FTP servers"
    echo "6) Harden DNS servers"
    echo "7) Quick security check"
    echo "8) Backup all configs"
    echo "9) HARDEN ALL detected services"
    echo ""
    read -p "Select option [1-9]: " choice
    
    case $choice in
        1) show_service_status ;;
        2) bash "$SCRIPT_DIR/harden-webserver.sh" ;;
        3) bash "$SCRIPT_DIR/harden-database.sh" ;;
        4) bash "$SCRIPT_DIR/harden-mail.sh" ;;
        5) bash "$SCRIPT_DIR/harden-ftp.sh" ;;
        6) bash "$SCRIPT_DIR/harden-dns.sh" ;;
        7) quick_security_check ;;
        8) backup_all_configs ;;
        9) harden_all_services ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
