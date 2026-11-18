#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Startup/Boot Persistence Audit
# Find malicious boot scripts, profile modifications, and init persistence

source "$(dirname "$0")/../utils/common.sh"
require_root

header "Startup and Boot Persistence Audit"

#=============================================================================
# CHECK PROFILE FILES
#=============================================================================
audit_profiles() {
    header "Auditing Profile Files"
    
    # System-wide profiles
    local system_profiles=(
        "/etc/profile"
        "/etc/profile.d/"
        "/etc/bash.bashrc"
        "/etc/bashrc"
        "/etc/zsh/zshenv"
        "/etc/zsh/zprofile"
        "/etc/environment"
    )
    
    for profile in "${system_profiles[@]}"; do
        if [ -f "$profile" ]; then
            info "Checking $profile..."
            
            # Check modification time
            local mtime=$(stat -c %Y "$profile" 2>/dev/null)
            local seven_days_ago=$(date -d '7 days ago' +%s 2>/dev/null)
            if [ -n "$mtime" ] && [ -n "$seven_days_ago" ] && [ "$mtime" -gt "$seven_days_ago" ]; then
                log_finding "Recently modified: $profile"
            fi
            
            # Check for suspicious content
            if grep -qE '(curl|wget|nc |netcat|/tmp/|/dev/shm/|base64|python.*-c|perl.*-e|bash.*-i|/dev/tcp)' "$profile" 2>/dev/null; then
                log_finding "Suspicious content in $profile"
                grep -nE '(curl|wget|nc |netcat|/tmp/|/dev/shm/|base64|python.*-c|perl.*-e|bash.*-i|/dev/tcp)' "$profile"
            fi
        elif [ -d "$profile" ]; then
            info "Checking directory $profile..."
            for file in "$profile"/*; do
                [ -f "$file" ] || continue
                
                # Check if from package
                local owned=false
                case "$PKG_MGR" in
                    apt) dpkg -S "$file" &>/dev/null && owned=true ;;
                    dnf|yum) rpm -qf "$file" &>/dev/null && owned=true ;;
                esac
                
                if ! $owned; then
                    log_finding "Unpackaged profile.d file: $file"
                    cat "$file"
                fi
            done
        fi
    done
    
    # User profile files
    info "Checking user profile files..."
    local user_profiles=(
        ".profile"
        ".bashrc"
        ".bash_profile"
        ".bash_login"
        ".bash_logout"
        ".zshrc"
        ".zprofile"
        ".zlogin"
        ".zlogout"
    )
    
    for home in /home/* /root; do
        [ -d "$home" ] || continue
        local user=$(basename "$home")
        [ "$home" == "/root" ] && user="root"
        
        for profile in "${user_profiles[@]}"; do
            local file="$home/$profile"
            [ -f "$file" ] || continue
            
            # Check for suspicious content
            if grep -qE '(curl|wget|nc |netcat|/tmp/|/dev/shm/|base64|python.*-c|perl.*-e|bash.*-i|/dev/tcp|nohup|&$)' "$file" 2>/dev/null; then
                log_finding "Suspicious content in $file (user: $user)"
                grep -nE '(curl|wget|nc |netcat|/tmp/|/dev/shm/|base64|python.*-c|perl.*-e|bash.*-i|/dev/tcp|nohup|&$)' "$file"
            fi
        done
    done
}

#=============================================================================
# CHECK RC.LOCAL
#=============================================================================
audit_rc_local() {
    header "Auditing rc.local"
    
    local rc_files=(
        "/etc/rc.local"
        "/etc/rc.d/rc.local"
    )
    
    for rc in "${rc_files[@]}"; do
        if [ -f "$rc" ]; then
            info "Contents of $rc:"
            cat "$rc"
            
            if [ -x "$rc" ]; then
                warn "$rc is executable!"
            fi
            
            # Check for suspicious content
            if grep -qE '(curl|wget|nc |netcat|/tmp/|/dev/shm/|base64|python|perl|ruby|nohup)' "$rc" 2>/dev/null; then
                log_finding "Suspicious content in $rc"
            fi
        fi
    done
}

#=============================================================================
# CHECK MOTD
#=============================================================================
audit_motd() {
    header "Auditing MOTD Scripts"
    
    # /etc/update-motd.d (Ubuntu/Debian)
    if [ -d /etc/update-motd.d ]; then
        info "MOTD scripts in /etc/update-motd.d:"
        ls -la /etc/update-motd.d/
        
        for script in /etc/update-motd.d/*; do
            [ -f "$script" ] || continue
            
            # Check if from package
            local owned=false
            case "$PKG_MGR" in
                apt) dpkg -S "$script" &>/dev/null && owned=true ;;
            esac
            
            if ! $owned; then
                log_finding "Unpackaged MOTD script: $script"
                cat "$script"
            fi
            
            # Check for suspicious content
            if grep -qE '(curl|wget|nc |netcat|/tmp/|/dev/shm/|base64)' "$script" 2>/dev/null; then
                log_finding "Suspicious content in MOTD script: $script"
            fi
        done
    fi
    
    # Static MOTD
    if [ -f /etc/motd ]; then
        info "Static MOTD:"
        cat /etc/motd
    fi
}

#=============================================================================
# CHECK INIT/INITTAB
#=============================================================================
audit_inittab() {
    header "Auditing Inittab"
    
    if [ -f /etc/inittab ]; then
        info "Contents of /etc/inittab:"
        grep -v "^#" /etc/inittab | grep -v "^$"
        
        # Check for suspicious entries
        if grep -qE '(curl|wget|nc |netcat|/tmp/|/dev/shm/)' /etc/inittab 2>/dev/null; then
            log_finding "Suspicious content in /etc/inittab"
        fi
    fi
}

#=============================================================================
# CHECK XINETD/INETD
#=============================================================================
audit_inetd() {
    header "Auditing inetd/xinetd"
    
    # inetd
    if [ -f /etc/inetd.conf ]; then
        log_finding "inetd.conf exists!"
        grep -v "^#" /etc/inetd.conf | grep -v "^$"
    fi
    
    # xinetd
    if [ -d /etc/xinetd.d ]; then
        info "xinetd services:"
        for service in /etc/xinetd.d/*; do
            [ -f "$service" ] || continue
            warn "xinetd service: $service"
            cat "$service"
        done
    fi
}

#=============================================================================
# CHECK SYSTEMD GENERATORS
#=============================================================================
audit_systemd_generators() {
    header "Auditing Systemd Generators"
    
    if [ "$INIT_SYSTEM" != "systemd" ]; then
        info "Not a systemd system, skipping..."
        return
    fi
    
    local generator_dirs=(
        "/etc/systemd/system-generators"
        "/usr/local/lib/systemd/system-generators"
        "/usr/lib/systemd/system-generators"
        "/lib/systemd/system-generators"
        "/run/systemd/system-generators"
        "/run/systemd/generator"
        "/run/systemd/generator.early"
        "/run/systemd/generator.late"
    )
    
    for dir in "${generator_dirs[@]}"; do
        [ -d "$dir" ] || continue
        info "Generators in $dir:"
        ls -la "$dir"
        
        for gen in "$dir"/*; do
            [ -f "$gen" ] || continue
            
            # Check if from package
            local owned=false
            case "$PKG_MGR" in
                apt) dpkg -S "$gen" &>/dev/null && owned=true ;;
                dnf|yum) rpm -qf "$gen" &>/dev/null && owned=true ;;
            esac
            
            if ! $owned; then
                log_finding "Unpackaged generator: $gen"
            fi
        done
    done
}

#=============================================================================
# CHECK UDEV RULES
#=============================================================================
audit_udev() {
    header "Auditing Udev Rules"
    
    local udev_dirs=(
        "/etc/udev/rules.d"
        "/lib/udev/rules.d"
        "/usr/lib/udev/rules.d"
    )
    
    for dir in "${udev_dirs[@]}"; do
        [ -d "$dir" ] || continue
        
        for rule in "$dir"/*; do
            [ -f "$rule" ] || continue
            
            # Check if from package
            local owned=false
            case "$PKG_MGR" in
                apt) dpkg -S "$rule" &>/dev/null && owned=true ;;
                dnf|yum) rpm -qf "$rule" &>/dev/null && owned=true ;;
            esac
            
            if ! $owned; then
                warn "Unpackaged udev rule: $rule"
            fi
            
            # Check for RUN commands with suspicious content
            if grep -q "RUN" "$rule" 2>/dev/null; then
                if grep "RUN" "$rule" | grep -qE '(curl|wget|nc |netcat|/tmp/|/dev/shm/|base64|python|perl)'; then
                    log_finding "Suspicious RUN in udev rule: $rule"
                    grep "RUN" "$rule"
                fi
            fi
        done
    done
}

#=============================================================================
# CHECK KERNEL MODULES AUTOLOAD
#=============================================================================
audit_module_autoload() {
    header "Auditing Kernel Module Autoload"
    
    local autoload_dirs=(
        "/etc/modules-load.d"
        "/usr/lib/modules-load.d"
        "/lib/modules-load.d"
    )
    
    for dir in "${autoload_dirs[@]}"; do
        [ -d "$dir" ] || continue
        info "Module autoload in $dir:"
        for conf in "$dir"/*; do
            [ -f "$conf" ] || continue
            warn "Autoload config: $conf"
            cat "$conf"
        done
    done
    
    # /etc/modules
    if [ -f /etc/modules ]; then
        info "Contents of /etc/modules:"
        cat /etc/modules
    fi
}

#=============================================================================
# CHECK XDG AUTOSTART
#=============================================================================
audit_xdg_autostart() {
    header "Auditing XDG Autostart"
    
    local xdg_dirs=(
        "/etc/xdg/autostart"
        "/usr/share/autostart"
    )
    
    for dir in "${xdg_dirs[@]}"; do
        [ -d "$dir" ] || continue
        info "XDG autostart in $dir:"
        for desktop in "$dir"/*.desktop; do
            [ -f "$desktop" ] || continue
            
            # Check if from package
            local owned=false
            case "$PKG_MGR" in
                apt) dpkg -S "$desktop" &>/dev/null && owned=true ;;
                dnf|yum) rpm -qf "$desktop" &>/dev/null && owned=true ;;
            esac
            
            if ! $owned; then
                warn "Unpackaged autostart: $desktop"
                cat "$desktop"
            fi
        done
    done
    
    # User autostart
    for home in /home/* /root; do
        local autostart="$home/.config/autostart"
        [ -d "$autostart" ] || continue
        
        local user=$(basename "$home")
        [ "$home" == "/root" ] && user="root"
        
        log_finding "User autostart for $user:"
        ls -la "$autostart"
        for desktop in "$autostart"/*.desktop; do
            [ -f "$desktop" ] || continue
            cat "$desktop"
        done
    done
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    echo ""
    echo "Startup Audit Options:"
    echo "1) Audit profile files"
    echo "2) Audit rc.local"
    echo "3) Audit MOTD scripts"
    echo "4) Audit inittab"
    echo "5) Audit inetd/xinetd"
    echo "6) Audit systemd generators"
    echo "7) Audit udev rules"
    echo "8) Audit module autoload"
    echo "9) Audit XDG autostart"
    echo "10) Run ALL audits"
    echo ""
    read -p "Select option [1-10]: " choice
    
    case $choice in
        1) audit_profiles ;;
        2) audit_rc_local ;;
        3) audit_motd ;;
        4) audit_inittab ;;
        5) audit_inetd ;;
        6) audit_systemd_generators ;;
        7) audit_udev ;;
        8) audit_module_autoload ;;
        9) audit_xdg_autostart ;;
        10)
            audit_profiles
            audit_rc_local
            audit_motd
            audit_inittab
            audit_inetd
            audit_systemd_generators
            audit_udev
            audit_module_autoload
            audit_xdg_autostart
            ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
