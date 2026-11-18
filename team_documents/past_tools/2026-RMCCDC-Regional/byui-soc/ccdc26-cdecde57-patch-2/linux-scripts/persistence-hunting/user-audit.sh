#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - User Audit
# Find backdoor users, modified accounts, and privilege escalation

source "$(dirname "$0")/../utils/common.sh"
require_root

header "User Account Audit"

#=============================================================================
# CHECK FOR UID 0 ACCOUNTS
#=============================================================================
check_uid0() {
    header "Checking for UID 0 Accounts"
    
    info "Users with UID 0:"
    awk -F: '$3 == 0 {print $1}' /etc/passwd | while read -r user; do
        if [ "$user" == "root" ]; then
            success "root (expected)"
        else
            log_finding "Non-root UID 0 account: $user"
        fi
    done
}

#=============================================================================
# CHECK FOR EMPTY PASSWORDS
#=============================================================================
check_empty_passwords() {
    header "Checking for Empty Passwords"
    
    # Check /etc/shadow
    awk -F: '($2 == "" || $2 == "!!" || length($2) < 13) && $2 !~ /^[!*]/ {print $1": "$2}' /etc/shadow 2>/dev/null | while read -r line; do
        log_finding "Weak/empty password: $line"
    done
    
    # Also check for accounts with no password required
    awk -F: '$2 == "" {print $1}' /etc/shadow 2>/dev/null | while read -r user; do
        log_finding "No password set for: $user"
    done
}

#=============================================================================
# CHECK FOR UNAUTHORIZED SHELL ACCESS
#=============================================================================
check_shell_access() {
    header "Checking Shell Access"
    
    info "System accounts with shells (should be /sbin/nologin or /bin/false):"
    while IFS=: read -r username _ uid _ _ _ shell; do
        # Skip if UID >= 1000 (human users) or root
        [ "$uid" -ge 1000 ] && continue
        [ "$uid" -eq 0 ] && continue
        
        # Check for login shells
        if [ "$shell" != "/usr/sbin/nologin" ] && \
           [ "$shell" != "/sbin/nologin" ] && \
           [ "$shell" != "/bin/false" ] && \
           [ -n "$shell" ]; then
            log_finding "System account with shell: $username (UID $uid) -> $shell"
        fi
    done < /etc/passwd
}

#=============================================================================
# CHECK SUDO/WHEEL GROUP
#=============================================================================
check_privileged_groups() {
    header "Checking Privileged Groups"
    
    info "sudo group members:"
    getent group sudo 2>/dev/null | cut -d: -f4 | tr ',' '\n' | while read -r user; do
        [ -z "$user" ] && continue
        warn "  $user"
    done
    
    info "wheel group members:"
    getent group wheel 2>/dev/null | cut -d: -f4 | tr ',' '\n' | while read -r user; do
        [ -z "$user" ] && continue
        warn "  $user"
    done
    
    info "adm group members:"
    getent group adm 2>/dev/null | cut -d: -f4 | tr ',' '\n' | while read -r user; do
        [ -z "$user" ] && continue
        echo "  $user"
    done
    
    info "root group members:"
    getent group root 2>/dev/null | cut -d: -f4 | tr ',' '\n' | while read -r user; do
        [ -z "$user" ] && continue
        log_finding "User in root group: $user"
    done
}

#=============================================================================
# CHECK SUDOERS
#=============================================================================
check_sudoers() {
    header "Checking Sudoers Configuration"
    
    info "Main sudoers file:"
    grep -v "^#" /etc/sudoers 2>/dev/null | grep -v "^$" | grep -v "^Defaults"
    
    info "Sudoers.d entries:"
    if [ -d /etc/sudoers.d ]; then
        for file in /etc/sudoers.d/*; do
            [ -f "$file" ] || continue
            warn "File: $file"
            cat "$file"
            echo ""
        done
    fi
    
    # Check for NOPASSWD
    info "Checking for NOPASSWD entries:"
    grep -r "NOPASSWD" /etc/sudoers /etc/sudoers.d/ 2>/dev/null | while read -r line; do
        log_finding "NOPASSWD sudo: $line"
    done
    
    # Check for ALL ALL permissions
    info "Checking for overly permissive entries:"
    grep -rE "ALL.*ALL.*ALL" /etc/sudoers /etc/sudoers.d/ 2>/dev/null | while read -r line; do
        warn "Broad sudo access: $line"
    done
}

#=============================================================================
# CHECK SSH KEYS
#=============================================================================
check_ssh_keys() {
    header "Checking SSH Authorized Keys"
    
    for home in /home/* /root; do
        local auth_keys="$home/.ssh/authorized_keys"
        local auth_keys2="$home/.ssh/authorized_keys2"
        
        local user=$(basename "$home")
        [ "$home" == "/root" ] && user="root"
        
        for keyfile in "$auth_keys" "$auth_keys2"; do
            if [ -f "$keyfile" ]; then
                local count=$(wc -l < "$keyfile")
                log_finding "SSH keys for $user: $count key(s) in $keyfile"
                
                # Show keys
                while read -r key; do
                    [ -z "$key" ] && continue
                    [[ "$key" == \#* ]] && continue
                    # Show just the comment/identifier
                    local key_comment=$(echo "$key" | awk '{print $3}')
                    warn "  Key: ${key_comment:-[no comment]}"
                done < "$keyfile"
            fi
        done
    done
    
    # Check for keys in unusual locations
    info "Searching for authorized_keys in unusual locations..."
    find / -name "authorized_keys*" 2>/dev/null | while read -r keyfile; do
        case "$keyfile" in
            /home/*/.ssh/authorized_keys*|/root/.ssh/authorized_keys*)
                # Normal location, already checked
                ;;
            *)
                log_finding "Unusual authorized_keys location: $keyfile"
                ;;
        esac
    done
}

#=============================================================================
# CHECK RECENTLY CREATED USERS
#=============================================================================
check_new_users() {
    header "Checking Recently Created Users"
    
    info "Users added in last 7 days (by home directory creation):"
    find /home -maxdepth 1 -type d -mtime -7 2>/dev/null | while read -r home; do
        [ "$home" == "/home" ] && continue
        local user=$(basename "$home")
        log_finding "Recent home directory: $home (user: $user)"
    done
    
    # Check /etc/passwd modification time
    local passwd_mtime=$(stat -c %Y /etc/passwd)
    local seven_days_ago=$(date -d '7 days ago' +%s)
    
    if [ "$passwd_mtime" -gt "$seven_days_ago" ]; then
        warn "/etc/passwd was modified in the last 7 days"
    fi
    
    # Check shadow modification
    local shadow_mtime=$(stat -c %Y /etc/shadow 2>/dev/null)
    if [ -n "$shadow_mtime" ] && [ "$shadow_mtime" -gt "$seven_days_ago" ]; then
        warn "/etc/shadow was modified in the last 7 days"
    fi
}

#=============================================================================
# CHECK PAM CONFIGURATION
#=============================================================================
check_pam() {
    header "Checking PAM Configuration"
    
    info "Checking for suspicious PAM modules..."
    
    # Check for pam_permit (allows all)
    if grep -r "pam_permit" /etc/pam.d/ 2>/dev/null | grep -v "^#"; then
        log_finding "pam_permit found in PAM config (allows authentication bypass)"
    fi
    
    # Check for custom PAM modules
    info "Non-standard PAM modules:"
    for pamfile in /etc/pam.d/*; do
        [ -f "$pamfile" ] || continue
        grep -v "^#" "$pamfile" | grep -oE "pam_[a-zA-Z0-9_]+\.so" | sort -u | while read -r module; do
            # Check if module exists
            if [ ! -f "/lib/security/$module" ] && \
               [ ! -f "/lib64/security/$module" ] && \
               [ ! -f "/usr/lib/security/$module" ] && \
               [ ! -f "/usr/lib64/security/$module" ]; then
                log_finding "Missing PAM module referenced in $pamfile: $module"
            fi
        done
    done
    
    # Check PAM module files for suspicious ones
    for libdir in /lib/security /lib64/security /usr/lib/security /usr/lib64/security; do
        [ -d "$libdir" ] || continue
        find "$libdir" -name "*.so" -mtime -7 2>/dev/null | while read -r mod; do
            log_finding "Recently modified PAM module: $mod"
        done
    done
}

#=============================================================================
# CHECK NSSWITCH
#=============================================================================
check_nsswitch() {
    header "Checking NSSwitch Configuration"
    
    if [ -f /etc/nsswitch.conf ]; then
        info "/etc/nsswitch.conf:"
        grep -v "^#" /etc/nsswitch.conf | grep -v "^$"
        
        # Check for unusual entries
        if grep -qE "(ldap|nis|hesiod|wins)" /etc/nsswitch.conf; then
            warn "External authentication sources configured in nsswitch.conf"
        fi
    fi
}

#=============================================================================
# FULL USER LISTING
#=============================================================================
list_all_users() {
    header "Full User Listing"
    
    printf "%-15s %-6s %-6s %-25s %s\n" "USERNAME" "UID" "GID" "HOME" "SHELL"
    printf "%-15s %-6s %-6s %-25s %s\n" "--------" "---" "---" "----" "-----"
    
    while IFS=: read -r username _ uid gid _ home shell; do
        # Color based on UID
        if [ "$uid" -eq 0 ]; then
            printf "${RED}%-15s %-6s %-6s %-25s %s${NC}\n" "$username" "$uid" "$gid" "$home" "$shell"
        elif [ "$uid" -lt 1000 ]; then
            printf "%-15s %-6s %-6s %-25s %s\n" "$username" "$uid" "$gid" "$home" "$shell"
        else
            printf "${YELLOW}%-15s %-6s %-6s %-25s %s${NC}\n" "$username" "$uid" "$gid" "$home" "$shell"
        fi
    done < /etc/passwd
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    echo ""
    echo "User Audit Options:"
    echo "1) Check for UID 0 accounts"
    echo "2) Check for empty passwords"
    echo "3) Check shell access"
    echo "4) Check privileged groups"
    echo "5) Check sudoers"
    echo "6) Check SSH keys"
    echo "7) Check recently created users"
    echo "8) Check PAM configuration"
    echo "9) Check NSSwitch"
    echo "10) List all users"
    echo "11) Run ALL audits"
    echo ""
    read -p "Select option [1-11]: " choice
    
    case $choice in
        1) check_uid0 ;;
        2) check_empty_passwords ;;
        3) check_shell_access ;;
        4) check_privileged_groups ;;
        5) check_sudoers ;;
        6) check_ssh_keys ;;
        7) check_new_users ;;
        8) check_pam ;;
        9) check_nsswitch ;;
        10) list_all_users ;;
        11)
            check_uid0
            check_empty_passwords
            check_shell_access
            check_privileged_groups
            check_sudoers
            check_ssh_keys
            check_new_users
            check_pam
            check_nsswitch
            ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
