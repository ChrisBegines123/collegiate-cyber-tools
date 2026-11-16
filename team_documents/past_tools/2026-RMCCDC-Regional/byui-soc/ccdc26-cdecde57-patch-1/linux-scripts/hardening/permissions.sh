#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - File Permission Hardening
# Fix dangerous permissions, secure sensitive files

source "$(dirname "$0")/../utils/common.sh"
require_root

header "File Permission Hardening"

#=============================================================================
# SECURE SENSITIVE FILES
#=============================================================================
secure_sensitive_files() {
    header "Securing Sensitive Files"
    
    # /etc/passwd - world readable, root writable
    chmod 644 /etc/passwd
    chown root:root /etc/passwd
    success "Secured /etc/passwd"
    
    # /etc/shadow - root only
    chmod 600 /etc/shadow
    chown root:root /etc/shadow
    success "Secured /etc/shadow"
    
    # /etc/group - world readable
    chmod 644 /etc/group
    chown root:root /etc/group
    success "Secured /etc/group"
    
    # /etc/gshadow - root only
    if [ -f /etc/gshadow ]; then
        chmod 600 /etc/gshadow
        chown root:root /etc/gshadow
        success "Secured /etc/gshadow"
    fi
    
    # SSH configs
    chmod 600 /etc/ssh/*_key 2>/dev/null
    chmod 644 /etc/ssh/*.pub 2>/dev/null
    chmod 644 /etc/ssh/sshd_config
    success "Secured SSH files"
    
    # Sudoers
    chmod 440 /etc/sudoers
    chmod 440 /etc/sudoers.d/* 2>/dev/null
    success "Secured sudoers"
    
    # Cron
    chmod 600 /etc/crontab
    chmod 700 /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.monthly /etc/cron.weekly 2>/dev/null
    success "Secured cron files"
    
    # Boot loader
    if [ -f /boot/grub/grub.cfg ]; then
        chmod 600 /boot/grub/grub.cfg
        success "Secured GRUB config"
    fi
    if [ -f /boot/grub2/grub.cfg ]; then
        chmod 600 /boot/grub2/grub.cfg
        success "Secured GRUB2 config"
    fi
    
    log_action "Secured sensitive files"
}

#=============================================================================
# FIND AND FIX WORLD-WRITABLE FILES
#=============================================================================
find_world_writable() {
    header "Finding World-Writable Files"
    
    info "World-writable files (excluding /proc, /sys, /dev)..."
    find / -xdev -type f -perm -0002 \
        ! -path "/proc/*" \
        ! -path "/sys/*" \
        ! -path "/dev/*" \
        2>/dev/null | while read -r file; do
        log_finding "World-writable file: $file"
    done
    
    info "World-writable directories without sticky bit..."
    find / -xdev -type d \( -perm -0002 -a ! -perm -1000 \) \
        ! -path "/proc/*" \
        ! -path "/sys/*" \
        ! -path "/dev/*" \
        2>/dev/null | while read -r dir; do
        log_finding "World-writable dir (no sticky): $dir"
    done
}

fix_world_writable() {
    header "Fixing World-Writable Files"
    
    info "Removing world-writable permission from files..."
    find / -xdev -type f -perm -0002 \
        ! -path "/proc/*" \
        ! -path "/sys/*" \
        ! -path "/dev/*" \
        2>/dev/null | while read -r file; do
        chmod o-w "$file"
        success "Fixed: $file"
    done
    
    info "Adding sticky bit to world-writable directories..."
    find / -xdev -type d \( -perm -0002 -a ! -perm -1000 \) \
        ! -path "/proc/*" \
        ! -path "/sys/*" \
        ! -path "/dev/*" \
        2>/dev/null | while read -r dir; do
        chmod +t "$dir"
        success "Fixed: $dir"
    done
    
    log_action "Fixed world-writable files and directories"
}

#=============================================================================
# FIND SUID/SGID BINARIES
#=============================================================================
audit_suid_sgid() {
    header "Auditing SUID/SGID Binaries"
    
    # Common legitimate SUID binaries
    local legitimate_suid=(
        "/usr/bin/sudo"
        "/usr/bin/su"
        "/usr/bin/passwd"
        "/usr/bin/chsh"
        "/usr/bin/chfn"
        "/usr/bin/newgrp"
        "/usr/bin/gpasswd"
        "/usr/bin/mount"
        "/usr/bin/umount"
        "/usr/bin/ping"
        "/usr/bin/crontab"
        "/usr/sbin/unix_chkpwd"
        "/usr/lib/openssh/ssh-keysign"
        "/usr/lib/dbus-1.0/dbus-daemon-launch-helper"
        "/usr/lib/policykit-1/polkit-agent-helper-1"
    )
    
    info "SUID binaries:"
    find / -xdev -type f -perm -4000 2>/dev/null | while read -r file; do
        local is_legitimate=false
        for legit in "${legitimate_suid[@]}"; do
            if [ "$file" == "$legit" ]; then
                is_legitimate=true
                break
            fi
        done
        
        if $is_legitimate; then
            echo "  [OK] $file"
        else
            log_finding "Non-standard SUID binary: $file"
        fi
    done
    
    info "SGID binaries:"
    find / -xdev -type f -perm -2000 2>/dev/null | while read -r file; do
        echo "  $file"
    done
    
    # Check for SUID in unusual locations
    info "Checking for SUID/SGID in unusual locations..."
    find /tmp /var/tmp /dev/shm /home -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | while read -r file; do
        log_finding "SUID/SGID in unusual location: $file"
    done
}

remove_unnecessary_suid() {
    header "Removing Unnecessary SUID/SGID"
    
    # Binaries that usually don't need SUID
    local remove_suid=(
        "/usr/bin/wall"
        "/usr/bin/write"
        "/usr/bin/chage"
        "/usr/bin/expiry"
    )
    
    for binary in "${remove_suid[@]}"; do
        if [ -f "$binary" ]; then
            if [ -u "$binary" ] || [ -g "$binary" ]; then
                chmod u-s,g-s "$binary"
                success "Removed SUID/SGID from: $binary"
            fi
        fi
    done
    
    log_action "Removed unnecessary SUID/SGID bits"
}

#=============================================================================
# CHECK FILE CAPABILITIES
#=============================================================================
audit_capabilities() {
    header "Auditing File Capabilities"
    
    if ! command -v getcap &>/dev/null; then
        warn "getcap not available"
        return
    fi
    
    info "Files with capabilities:"
    getcap -r / 2>/dev/null | while read -r line; do
        local file=$(echo "$line" | awk '{print $1}')
        local caps=$(echo "$line" | cut -d'=' -f2)
        
        # Check for dangerous capabilities
        if echo "$caps" | grep -qE '(cap_sys_admin|cap_setuid|cap_setgid|cap_sys_ptrace|cap_sys_module)'; then
            log_finding "Dangerous capability: $line"
        else
            echo "  $line"
        fi
    done
    
    # Check for capabilities in unusual locations
    find /tmp /var/tmp /dev/shm /home -type f 2>/dev/null | while read -r file; do
        local cap=$(getcap "$file" 2>/dev/null)
        if [ -n "$cap" ]; then
            log_finding "Capability in unusual location: $cap"
        fi
    done
}

#=============================================================================
# SECURE HOME DIRECTORIES
#=============================================================================
secure_home_directories() {
    header "Securing Home Directories"
    
    for home in /home/*; do
        if [ -d "$home" ]; then
            local user=$(basename "$home")
            
            # Set home directory to 700
            chmod 700 "$home"
            chown "$user:$user" "$home"
            
            # Secure .ssh directory if exists
            if [ -d "$home/.ssh" ]; then
                chmod 700 "$home/.ssh"
                chmod 600 "$home/.ssh"/* 2>/dev/null
                chown -R "$user:$user" "$home/.ssh"
            fi
            
            # Remove world-readable from sensitive dotfiles
            for dotfile in .bash_history .mysql_history .psql_history .viminfo; do
                if [ -f "$home/$dotfile" ]; then
                    chmod 600 "$home/$dotfile"
                fi
            done
            
            success "Secured: $home"
        fi
    done
    
    # Secure root home
    chmod 700 /root
    chmod 700 /root/.ssh 2>/dev/null
    chmod 600 /root/.ssh/* 2>/dev/null
    
    log_action "Secured home directories"
}

#=============================================================================
# CHECK FOR HIDDEN FILES IN UNUSUAL PLACES
#=============================================================================
find_hidden_files() {
    header "Finding Hidden Files in Unusual Places"
    
    info "Hidden files in /tmp, /var/tmp, /dev/shm..."
    find /tmp /var/tmp /dev/shm -name ".*" -type f 2>/dev/null | while read -r file; do
        log_finding "Hidden file: $file"
    done
    
    info "Hidden directories in /..."
    find / -maxdepth 3 -name ".*" -type d \
        ! -path "/home/*" \
        ! -path "/root/*" \
        ! -path "/proc/*" \
        ! -path "/sys/*" \
        2>/dev/null | grep -v "^/\." | while read -r dir; do
        log_finding "Hidden directory: $dir"
    done
}

#=============================================================================
# CHECK FOR IMMUTABLE FILES
#=============================================================================
check_immutable_files() {
    header "Checking for Immutable Files"
    
    if ! command -v lsattr &>/dev/null; then
        warn "lsattr not available"
        return
    fi
    
    info "Looking for immutable files (attacker persistence)..."
    
    # Check critical system files
    for file in /etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config; do
        if [ -f "$file" ]; then
            local attrs=$(lsattr "$file" 2>/dev/null | awk '{print $1}')
            if echo "$attrs" | grep -q "i"; then
                log_finding "Immutable flag set on: $file"
            fi
        fi
    done
    
    # Find all immutable files using recursive lsattr (much faster)
    info "Scanning for all immutable files..."
    # lsattr -R is faster than calling lsattr per-file
    # Output format: "----i--------e-- /path/to/file" - 'i' in position 5 means immutable
    lsattr -R / 2>/dev/null | grep -E '^....i' | while read -r line; do
        local file=$(echo "$line" | awk '{print $2}')
        log_finding "Immutable file: $file"
    done
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    echo ""
    echo "File Permission Options:"
    echo "1) Secure sensitive files"
    echo "2) Find world-writable files"
    echo "3) Fix world-writable files"
    echo "4) Audit SUID/SGID binaries"
    echo "5) Remove unnecessary SUID/SGID"
    echo "6) Audit file capabilities"
    echo "7) Secure home directories"
    echo "8) Find hidden files"
    echo "9) Check immutable files"
    echo "10) Run ALL"
    echo ""
    read -p "Select option [1-10]: " choice
    
    case $choice in
        1) secure_sensitive_files ;;
        2) find_world_writable ;;
        3) fix_world_writable ;;
        4) audit_suid_sgid ;;
        5) remove_unnecessary_suid ;;
        6) audit_capabilities ;;
        7) secure_home_directories ;;
        8) find_hidden_files ;;
        9) check_immutable_files ;;
        10)
            secure_sensitive_files
            find_world_writable
            fix_world_writable
            audit_suid_sgid
            audit_capabilities
            secure_home_directories
            find_hidden_files
            check_immutable_files
            ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
