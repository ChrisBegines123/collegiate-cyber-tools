#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Service Management
# Disable unnecessary services, audit running services

source "$(dirname "$0")/../utils/common.sh"
require_root

header "Service Management"

#=============================================================================
# CONFIGURATION
#=============================================================================
# Services that are commonly unnecessary/dangerous (will prompt before disabling)
# NOTE: Web servers (apache2, httpd, nginx), mail servers (postfix, dovecot),
#       FTP (vsftpd), and DNS (named, bind9) are EXCLUDED because they are
#       typically SCORED SERVICES in CCDC competitions!
DANGEROUS_SERVICES=(
    "telnet" "telnetd" "xinetd" "inetd"
    "rsh" "rlogin" "rexec" "rsh-server"
    "tftp" "tftpd" "atftpd"
    # "vsftpd" "proftpd" "pure-ftpd" "ftpd"  # REMOVED - FTP may be scored!
    "nfs" "nfs-server" "nfs-kernel-server" "rpcbind"
    "smbd" "nmbd" "samba"
    "snmpd"
    "avahi-daemon" "cups" "cups-browsed"
    "bluetooth" "bluez"
    # "apache2" "httpd" "nginx"  # REMOVED - Web servers are SCORED!
    # "postfix" "dovecot"        # NOT ADDED - Mail servers are SCORED!
)

# Services to keep (will never be disabled automatically)
ESSENTIAL_SERVICES=(
    "sshd" "ssh"
    "networking" "network" "NetworkManager"
    "systemd-journald" "rsyslog" "syslog-ng"
    "cron" "crond"
    "dbus"
)

#=============================================================================
# LIST ALL SERVICES
#=============================================================================
list_services() {
    header "Listing All Services"
    
    case "$INIT_SYSTEM" in
        systemd)
            info "Active services:"
            systemctl list-units --type=service --state=running --no-pager
            
            echo ""
            info "Enabled services:"
            systemctl list-unit-files --type=service --state=enabled --no-pager
            ;;
        openrc)
            info "Running services:"
            rc-status
            
            info "All services:"
            rc-update show
            ;;
        sysvinit)
            info "Running services:"
            service --status-all 2>/dev/null
            ;;
    esac
}

#=============================================================================
# AUDIT SERVICES
#=============================================================================
audit_services() {
    header "Auditing Services"
    
    info "Checking for dangerous/unnecessary services..."
    
    for svc in "${DANGEROUS_SERVICES[@]}"; do
        case "$INIT_SYSTEM" in
            systemd)
                if systemctl is-active "$svc" &>/dev/null; then
                    log_finding "Dangerous service RUNNING: $svc"
                elif systemctl is-enabled "$svc" &>/dev/null; then
                    log_finding "Dangerous service ENABLED: $svc"
                fi
                ;;
            openrc)
                if rc-service "$svc" status &>/dev/null; then
                    log_finding "Dangerous service RUNNING: $svc"
                fi
                ;;
            sysvinit)
                if service "$svc" status &>/dev/null; then
                    log_finding "Dangerous service RUNNING: $svc"
                fi
                ;;
        esac
    done
    
    info "Checking for services listening on network..."
    get_listening_ports
    
    info "Checking for unusual services..."
    case "$INIT_SYSTEM" in
        systemd)
            # Look for user-created services
            if [ -d /etc/systemd/system ]; then
                for f in /etc/systemd/system/*.service; do
                    [ -f "$f" ] || continue
                    if ! dpkg -S "$f" &>/dev/null && ! rpm -qf "$f" &>/dev/null; then
                        log_finding "Custom service file: $f"
                    fi
                done
            fi
            
            # Check for suspicious ExecStart
            for f in /etc/systemd/system/*.service /lib/systemd/system/*.service; do
                [ -f "$f" ] || continue
                if grep -qE 'ExecStart=.*(nc |ncat |netcat |/tmp/|/dev/shm/|curl.*\||wget.*\|)' "$f" 2>/dev/null; then
                    log_finding "Suspicious ExecStart in: $f"
                fi
            done
            ;;
    esac
}

#=============================================================================
# DISABLE DANGEROUS SERVICES
#=============================================================================
disable_dangerous_services() {
    header "Disabling Dangerous Services"
    
    for svc in "${DANGEROUS_SERVICES[@]}"; do
        local is_active=false
        local is_enabled=false
        
        case "$INIT_SYSTEM" in
            systemd)
                systemctl is-active "$svc" &>/dev/null && is_active=true
                systemctl is-enabled "$svc" &>/dev/null && is_enabled=true
                ;;
            openrc)
                rc-service "$svc" status &>/dev/null && is_active=true
                ;;
            sysvinit)
                service "$svc" status &>/dev/null && is_active=true
                ;;
        esac
        
        if $is_active || $is_enabled; then
            warn "Found: $svc (active=$is_active, enabled=$is_enabled)"
            read -p "Disable $svc? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                service_stop "$svc"
                success "Disabled: $svc"
                log_action "Disabled service: $svc"
            fi
        fi
    done
}

#=============================================================================
# CHECK FOR BACKDOOR SERVICES
#=============================================================================
check_backdoor_services() {
    header "Checking for Backdoor Services"
    
    case "$INIT_SYSTEM" in
        systemd)
            # Check all service files for suspicious patterns
            info "Scanning service files for suspicious content..."
            
            local suspicious_patterns=(
                "/tmp/"
                "/dev/shm/"
                "/var/tmp/"
                "curl.*|.*sh"
                "wget.*|.*sh"
                "base64"
                "nc -"
                "ncat"
                "netcat"
                "/bin/bash -i"
                "python.*-c"
                "perl.*-e"
                "ruby.*-e"
            )
            
            for pattern in "${suspicious_patterns[@]}"; do
                grep -rl "$pattern" /etc/systemd/system/ /lib/systemd/system/ 2>/dev/null | while read -r file; do
                    log_finding "Suspicious pattern '$pattern' in: $file"
                done
            done
            
            # Check for recently modified service files
            info "Recently modified service files (last 7 days):"
            find /etc/systemd/system /lib/systemd/system -name "*.service" -mtime -7 2>/dev/null | while read -r f; do
                warn "Modified: $f ($(stat -c %y "$f" 2>/dev/null))"
            done
            
            # Check for services running from unusual locations
            info "Checking service binaries..."
            systemctl list-units --type=service --state=running --no-pager | \
            awk '{print $1}' | while read -r svc; do
                local exec_path=$(systemctl show "$svc" -p ExecStart 2>/dev/null | sed 's/ExecStart=.*path=\([^ ]*\).*/\1/' | head -1)
                if [[ "$exec_path" == /tmp/* ]] || [[ "$exec_path" == /dev/shm/* ]] || [[ "$exec_path" == /var/tmp/* ]]; then
                    log_finding "Service running from suspicious path: $svc -> $exec_path"
                fi
            done
            ;;
    esac
    
    # Check for services with suspicious names
    info "Checking for suspiciously named services..."
    case "$INIT_SYSTEM" in
        systemd)
            systemctl list-units --all --no-pager | grep -iE '(backdoor|shell|reverse|bind|payload|meterpreter|beacon)' && \
                log_finding "Suspiciously named service found"
            ;;
    esac
}

#=============================================================================
# VERIFY ESSENTIAL SERVICES
#=============================================================================
verify_essential_services() {
    header "Verifying Essential Services"
    
    for svc in "${ESSENTIAL_SERVICES[@]}"; do
        local status=$(service_status "$svc" 2>/dev/null)
        if [ "$status" == "active" ] || [ "$status" == "running" ]; then
            success "$svc is running"
        else
            # Try to start it
            case "$INIT_SYSTEM" in
                systemd)
                    if systemctl list-unit-files | grep -q "^$svc"; then
                        warn "$svc exists but not running"
                    fi
                    ;;
            esac
        fi
    done
}

#=============================================================================
# HARDEN SPECIFIC SERVICES
#=============================================================================
harden_cron() {
    header "Hardening Cron"
    
    # Restrict cron access
    if [ ! -f /etc/cron.allow ]; then
        echo "root" > /etc/cron.allow
        chmod 600 /etc/cron.allow
        success "Created /etc/cron.allow (root only)"
    fi
    
    # Remove cron.deny (cron.allow takes precedence)
    rm -f /etc/cron.deny
    
    # Secure cron directories
    chmod 700 /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.monthly /etc/cron.weekly 2>/dev/null
    
    log_action "Hardened cron"
}

harden_at() {
    header "Hardening at"
    
    # Restrict at access
    if [ ! -f /etc/at.allow ]; then
        echo "root" > /etc/at.allow
        chmod 600 /etc/at.allow
        success "Created /etc/at.allow (root only)"
    fi
    
    rm -f /etc/at.deny
    
    log_action "Hardened at"
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    echo ""
    echo "Service Management Options:"
    echo "1) List all services"
    echo "2) Audit services (find dangerous ones)"
    echo "3) Disable dangerous services"
    echo "4) Check for backdoor services"
    echo "5) Verify essential services running"
    echo "6) Harden cron/at"
    echo "7) Run ALL"
    echo ""
    read -p "Select option [1-7]: " choice
    
    case $choice in
        1) list_services ;;
        2) audit_services ;;
        3) disable_dangerous_services ;;
        4) check_backdoor_services ;;
        5) verify_essential_services ;;
        6) harden_cron; harden_at ;;
        7)
            audit_services
            check_backdoor_services
            disable_dangerous_services
            verify_essential_services
            harden_cron
            harden_at
            ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
