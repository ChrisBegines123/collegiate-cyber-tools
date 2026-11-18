#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Service Restoration
# Quickly restore critical services

source "$(dirname "$0")/../utils/common.sh"
require_root

header "Service Restoration"

#=============================================================================
# CHECK SERVICE STATUS
#=============================================================================
check_service() {
    local service="$1"
    
    case "$INIT_SYSTEM" in
        systemd)
            systemctl is-active "$service" 2>/dev/null
            ;;
        openrc)
            rc-service "$service" status &>/dev/null && echo "active" || echo "inactive"
            ;;
        sysvinit)
            service "$service" status &>/dev/null && echo "active" || echo "inactive"
            ;;
    esac
}

#=============================================================================
# RESTORE SSH
#=============================================================================
restore_ssh() {
    header "Restoring SSH Service"
    
    # Check if sshd is installed
    if ! command -v sshd &>/dev/null; then
        info "Installing OpenSSH server..."
        pkg_install openssh-server
    fi
    
    # Check config validity
    info "Checking SSH configuration..."
    if sshd -t 2>/dev/null; then
        success "SSH configuration valid"
    else
        warn "SSH configuration invalid, using defaults"
        # Backup and restore default config
        backup_file /etc/ssh/sshd_config
        cat > /etc/ssh/sshd_config << 'EOF'
Port 22
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
UsePAM yes
X11Forwarding no
Subsystem sftp /usr/lib/openssh/sftp-server
EOF
    fi
    
    # Start service
    service_start sshd || service_start ssh
    
    if [ "$(check_service sshd)" == "active" ] || [ "$(check_service ssh)" == "active" ]; then
        success "SSH service is running"
    else
        error "Failed to start SSH service"
    fi
    
    # Check listening
    ss -tlnp | grep :22
    
    log_action "Restored SSH service"
}

#=============================================================================
# RESTORE APACHE
#=============================================================================
restore_apache() {
    header "Restoring Apache Service"
    
    local service_name="apache2"
    command -v httpd &>/dev/null && service_name="httpd"
    
    # Check if installed
    if ! command -v apache2 &>/dev/null && ! command -v httpd &>/dev/null; then
        info "Installing Apache..."
        pkg_install apache2 || pkg_install httpd
    fi
    
    # Check config
    info "Checking Apache configuration..."
    if apache2ctl configtest 2>/dev/null || httpd -t 2>/dev/null; then
        success "Apache configuration valid"
    else
        warn "Apache configuration has errors"
    fi
    
    # Start service
    service_start "$service_name"
    
    if [ "$(check_service $service_name)" == "active" ]; then
        success "Apache is running"
    else
        error "Failed to start Apache"
    fi
    
    ss -tlnp | grep :80
    
    log_action "Restored Apache service"
}

#=============================================================================
# RESTORE NGINX
#=============================================================================
restore_nginx() {
    header "Restoring Nginx Service"
    
    if ! command -v nginx &>/dev/null; then
        info "Installing Nginx..."
        pkg_install nginx
    fi
    
    info "Checking Nginx configuration..."
    if nginx -t 2>/dev/null; then
        success "Nginx configuration valid"
    else
        warn "Nginx configuration has errors"
    fi
    
    service_start nginx
    
    if [ "$(check_service nginx)" == "active" ]; then
        success "Nginx is running"
    else
        error "Failed to start Nginx"
    fi
    
    ss -tlnp | grep :80
    
    log_action "Restored Nginx service"
}

#=============================================================================
# RESTORE MYSQL/MARIADB
#=============================================================================
restore_mysql() {
    header "Restoring MySQL/MariaDB Service"
    
    local service_name="mysql"
    [ -f /etc/init.d/mariadb ] && service_name="mariadb"
    systemctl list-unit-files | grep -q mariadb && service_name="mariadb"
    
    # Check if installed
    if ! command -v mysql &>/dev/null && ! command -v mariadb &>/dev/null; then
        info "Installing MariaDB..."
        pkg_install mariadb-server || pkg_install mysql-server
    fi
    
    service_start "$service_name"
    
    if [ "$(check_service $service_name)" == "active" ]; then
        success "MySQL/MariaDB is running"
    else
        error "Failed to start MySQL/MariaDB"
    fi
    
    ss -tlnp | grep :3306
    
    log_action "Restored MySQL/MariaDB service"
}

#=============================================================================
# RESTORE DNS
#=============================================================================
restore_dns() {
    header "Restoring DNS Service"
    
    # Check if bind/named is installed
    if command -v named &>/dev/null; then
        info "Checking named configuration..."
        named-checkconf 2>/dev/null
        service_start named
    elif command -v systemd-resolved &>/dev/null; then
        service_start systemd-resolved
    fi
    
    # Restore /etc/resolv.conf if needed
    if [ ! -s /etc/resolv.conf ]; then
        warn "Empty resolv.conf, adding defaults..."
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
        echo "nameserver 8.8.4.4" >> /etc/resolv.conf
    fi
    
    info "Current DNS configuration:"
    cat /etc/resolv.conf
    
    log_action "Restored DNS configuration"
}

#=============================================================================
# CHECK ALL SERVICES
#=============================================================================
check_all_services() {
    header "Checking All Common Services"
    
    local services=("sshd" "ssh" "apache2" "httpd" "nginx" "mysql" "mariadb" "postgresql" "named" "bind9" "vsftpd" "postfix" "dovecot")
    
    for svc in "${services[@]}"; do
        local status=$(check_service "$svc")
        if [ "$status" == "active" ]; then
            success "$svc: running"
        elif systemctl list-unit-files 2>/dev/null | grep -q "^$svc"; then
            warn "$svc: stopped"
        fi
    done
}

#=============================================================================
# QUICK RESTART
#=============================================================================
quick_restart() {
    header "Quick Service Restart"
    
    read -p "Enter service name to restart: " service_name
    
    if [ -z "$service_name" ]; then
        error "No service name provided"
        return
    fi
    
    info "Stopping $service_name..."
    service_stop "$service_name"
    sleep 2
    
    info "Starting $service_name..."
    service_start "$service_name"
    
    local status=$(check_service "$service_name")
    if [ "$status" == "active" ]; then
        success "$service_name is running"
    else
        error "Failed to start $service_name"
    fi
    
    log_action "Restarted service: $service_name"
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    echo ""
    echo "Service Restoration Options:"
    echo "1) Check all service status"
    echo "2) Restore SSH"
    echo "3) Restore Apache"
    echo "4) Restore Nginx"
    echo "5) Restore MySQL/MariaDB"
    echo "6) Restore DNS"
    echo "7) Quick restart (any service)"
    echo ""
    read -p "Select option [1-7]: " choice
    
    case $choice in
        1) check_all_services ;;
        2) restore_ssh ;;
        3) restore_apache ;;
        4) restore_nginx ;;
        5) restore_mysql ;;
        6) restore_dns ;;
        7) quick_restart ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
