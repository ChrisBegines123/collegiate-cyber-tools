#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Service Audit
# Find malicious systemd services and init scripts

source "$(dirname "$0")/../utils/common.sh"
require_root

header "Service Persistence Audit"

#=============================================================================
# SYSTEMD SERVICE AUDIT
#=============================================================================
audit_systemd_services() {
    header "Auditing Systemd Services"
    
    if [ "$INIT_SYSTEM" != "systemd" ]; then
        info "Not a systemd system, skipping..."
        return
    fi
    
    # Check custom service files in /etc/systemd/system
    info "Custom services in /etc/systemd/system:"
    for service in /etc/systemd/system/*.service; do
        [ -f "$service" ] || continue
        
        # Check if it's owned by a package
        local owned=false
        case "$PKG_MGR" in
            apt) dpkg -S "$service" &>/dev/null && owned=true ;;
            dnf|yum) rpm -qf "$service" &>/dev/null && owned=true ;;
        esac
        
        if ! $owned; then
            warn "Unpackaged service: $service"
            cat "$service"
            echo ""
        fi
    done
    
    # Check for suspicious ExecStart paths
    info "Checking for suspicious service configurations..."
    local suspicious_paths=(
        "/tmp/"
        "/dev/shm/"
        "/var/tmp/"
        "/home/"
        "/root/"
    )
    
    for path in "${suspicious_paths[@]}"; do
        grep -rl "ExecStart=.*$path" /etc/systemd/system/ /lib/systemd/system/ 2>/dev/null | while read -r file; do
            log_finding "Service with suspicious path '$path': $file"
            grep "ExecStart" "$file"
        done
    done
    
    # Check for suspicious commands in services
    local suspicious_cmds=(
        "curl"
        "wget"
        "nc "
        "ncat"
        "netcat"
        "base64"
        "python.*-c"
        "perl.*-e"
        "bash.*-i"
        "| *sh"
    )
    
    for cmd in "${suspicious_cmds[@]}"; do
        grep -rl "$cmd" /etc/systemd/system/*.service /lib/systemd/system/*.service 2>/dev/null | while read -r file; do
            log_finding "Service with suspicious command '$cmd': $file"
        done
    done
    
    # Recently modified service files
    info "Recently modified services (last 7 days):"
    find /etc/systemd/system /lib/systemd/system -name "*.service" -mtime -7 2>/dev/null | while read -r f; do
        warn "Modified: $f ($(stat -c %y "$f" 2>/dev/null))"
    done
    
    # Check for services running as root that shouldn't
    info "Services running as root:"
    systemctl list-units --type=service --state=running --no-pager | while read -r line; do
        local svc=$(echo "$line" | awk '{print $1}')
        local user=$(systemctl show "$svc" -p User 2>/dev/null | cut -d= -f2)
        if [ -z "$user" ] || [ "$user" == "root" ]; then
            echo "  $svc (runs as root)"
        fi
    done
}

#=============================================================================
# INIT.D SCRIPTS AUDIT
#=============================================================================
audit_initd() {
    header "Auditing Init.d Scripts"
    
    if [ ! -d /etc/init.d ]; then
        info "No init.d directory found"
        return
    fi
    
    info "Init scripts in /etc/init.d:"
    ls -la /etc/init.d/
    
    # Check for suspicious scripts
    info "Checking for suspicious init scripts..."
    for script in /etc/init.d/*; do
        [ -f "$script" ] || continue
        
        # Check if owned by package
        local owned=false
        case "$PKG_MGR" in
            apt) dpkg -S "$script" &>/dev/null && owned=true ;;
            dnf|yum) rpm -qf "$script" &>/dev/null && owned=true ;;
        esac
        
        if ! $owned; then
            log_finding "Unpackaged init script: $script"
        fi
        
        # Check for suspicious content
        if grep -qE '(curl|wget|nc |netcat|/tmp/|/dev/shm/|base64)' "$script"; then
            log_finding "Suspicious content in: $script"
        fi
    done
    
    # Check rc.local
    if [ -f /etc/rc.local ]; then
        info "Contents of /etc/rc.local:"
        cat /etc/rc.local
        
        # Check if it's enabled
        if [ -x /etc/rc.local ]; then
            warn "/etc/rc.local is executable!"
        fi
        
        # Check for suspicious content
        if grep -qE '(curl|wget|nc |netcat|/tmp/|/dev/shm/|base64|python|perl|ruby)' /etc/rc.local; then
            log_finding "Suspicious content in /etc/rc.local"
        fi
    fi
}

#=============================================================================
# OPENRC AUDIT (Alpine)
#=============================================================================
audit_openrc() {
    header "Auditing OpenRC Services"
    
    if [ "$INIT_SYSTEM" != "openrc" ]; then
        info "Not an OpenRC system, skipping..."
        return
    fi
    
    info "OpenRC services status:"
    rc-status --all
    
    info "Local services in /etc/local.d:"
    if [ -d /etc/local.d ]; then
        ls -la /etc/local.d/
        for script in /etc/local.d/*; do
            [ -f "$script" ] || continue
            warn "Local startup script: $script"
            cat "$script"
        done
    fi
}

#=============================================================================
# SOCKET ACTIVATION AUDIT
#=============================================================================
audit_sockets() {
    header "Auditing Socket Activation"
    
    if [ "$INIT_SYSTEM" != "systemd" ]; then
        return
    fi
    
    info "Active socket units:"
    systemctl list-sockets --no-pager
    
    # Check for custom sockets
    info "Custom socket units:"
    for socket in /etc/systemd/system/*.socket; do
        [ -f "$socket" ] || continue
        warn "Custom socket: $socket"
        cat "$socket"
    done
}

#=============================================================================
# USER SERVICES
#=============================================================================
audit_user_services() {
    header "Auditing User-Level Services"
    
    if [ "$INIT_SYSTEM" != "systemd" ]; then
        return
    fi
    
    for user_home in /home/* /root; do
        local user_systemd="$user_home/.config/systemd/user"
        if [ -d "$user_systemd" ]; then
            local user=$(basename "$user_home")
            [ "$user_home" == "/root" ] && user="root"
            
            warn "User services for $user:"
            ls -la "$user_systemd/"
            
            for service in "$user_systemd"/*.service; do
                [ -f "$service" ] || continue
                log_finding "User service: $service"
                cat "$service"
            done
        fi
    done
}

#=============================================================================
# DBUS SERVICES
#=============================================================================
audit_dbus_services() {
    header "Auditing D-Bus Services"
    
    local dbus_dirs=(
        "/usr/share/dbus-1/system-services"
        "/usr/share/dbus-1/services"
        "/etc/dbus-1/system.d"
        "/etc/dbus-1/session.d"
    )
    
    for dir in "${dbus_dirs[@]}"; do
        if [ -d "$dir" ]; then
            info "D-Bus configs in $dir:"
            for conf in "$dir"/*; do
                [ -f "$conf" ] || continue
                
                # Check if it's packaged
                local owned=false
                case "$PKG_MGR" in
                    apt) dpkg -S "$conf" &>/dev/null && owned=true ;;
                    dnf|yum) rpm -qf "$conf" &>/dev/null && owned=true ;;
                esac
                
                if ! $owned; then
                    log_finding "Unpackaged D-Bus config: $conf"
                    cat "$conf"
                fi
            done
        fi
    done
}

#=============================================================================
# REMOVE MALICIOUS SERVICE
#=============================================================================
remove_service() {
    header "Remove Malicious Service"
    
    read -p "Enter service name to remove: " service_name
    
    if [ -z "$service_name" ]; then
        error "No service name provided"
        return
    fi
    
    # Stop and disable
    systemctl stop "$service_name" 2>/dev/null
    systemctl disable "$service_name" 2>/dev/null
    
    # Find and remove service file
    local service_files=(
        "/etc/systemd/system/${service_name}.service"
        "/lib/systemd/system/${service_name}.service"
        "/etc/init.d/${service_name}"
    )
    
    for file in "${service_files[@]}"; do
        if [ -f "$file" ]; then
            warn "Found: $file"
            cat "$file"
            read -p "Remove this file? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -f "$file"
                success "Removed: $file"
                log_action "Removed service file: $file"
            fi
        fi
    done
    
    # Reload systemd
    systemctl daemon-reload 2>/dev/null
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    echo ""
    echo "Service Audit Options:"
    echo "1) Audit systemd services"
    echo "2) Audit init.d scripts"
    echo "3) Audit OpenRC services"
    echo "4) Audit socket activation"
    echo "5) Audit user-level services"
    echo "6) Audit D-Bus services"
    echo "7) Remove malicious service"
    echo "8) Run ALL audits"
    echo ""
    read -p "Select option [1-8]: " choice
    
    case $choice in
        1) audit_systemd_services ;;
        2) audit_initd ;;
        3) audit_openrc ;;
        4) audit_sockets ;;
        5) audit_user_services ;;
        6) audit_dbus_services ;;
        7) remove_service ;;
        8)
            audit_systemd_services
            audit_initd
            audit_openrc
            audit_sockets
            audit_user_services
            audit_dbus_services
            ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
