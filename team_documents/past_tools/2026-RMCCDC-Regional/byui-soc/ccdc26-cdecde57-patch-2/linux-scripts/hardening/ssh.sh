#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - SSH Hardening
# Secure SSH configuration across distributions

source "$(dirname "$0")/../utils/common.sh"
require_root

header "SSH Hardening"

SSHD_CONFIG="/etc/ssh/sshd_config"

#=============================================================================
# CONFIGURATION
#=============================================================================
# Set to your team's IP range if known (CIDR notation)
ALLOWED_SSH_NETWORKS=""  # e.g., "10.0.0.0/8 192.168.1.0/24"

# SSH port (change if needed, but remember for firewall!)
SSH_PORT="22"

#=============================================================================
# BACKUP EXISTING CONFIG
#=============================================================================
backup_ssh_config() {
    backup_file "$SSHD_CONFIG"
    backup_file /etc/ssh/sshd_config.d/*.conf 2>/dev/null
}

#=============================================================================
# AUDIT CURRENT SSH CONFIG
#=============================================================================
audit_ssh() {
    header "Auditing Current SSH Configuration"
    
    if [ ! -f "$SSHD_CONFIG" ]; then
        error "SSH config not found at $SSHD_CONFIG"
        return 1
    fi
    
    info "Current SSH settings:"
    
    # Check critical settings
    local settings=("PermitRootLogin" "PasswordAuthentication" "PubkeyAuthentication" 
                    "PermitEmptyPasswords" "X11Forwarding" "UsePAM" "Port"
                    "AllowUsers" "AllowGroups" "Protocol")
    
    for setting in "${settings[@]}"; do
        local value=$(grep -i "^${setting}" "$SSHD_CONFIG" 2>/dev/null | tail -1)
        if [ -n "$value" ]; then
            echo "  $value"
        else
            echo "  $setting: (not explicitly set - using default)"
        fi
    done
    
    # Check for suspicious settings
    info "Checking for suspicious SSH configurations..."
    
    # Check authorized_keys for all users
    info "Checking authorized_keys files..."
    for home in /home/* /root; do
        if [ -f "$home/.ssh/authorized_keys" ]; then
            local count=$(wc -l < "$home/.ssh/authorized_keys")
            local user=$(basename "$home")
            [ "$home" == "/root" ] && user="root"
            warn "Found $count key(s) in $home/.ssh/authorized_keys"
            log_finding "SSH keys found for $user: $count keys"
        fi
    done
    
    # Check for SSH backdoor ports
    info "Checking for additional SSH instances..."
    if command -v ss &>/dev/null; then
        ss -tlnp | grep -i ssh
    fi
}

#=============================================================================
# HARDEN SSHD CONFIG
#=============================================================================
harden_sshd_config() {
    header "Hardening SSH Configuration"
    
    backup_ssh_config
    
    # Create hardened config
    cat > "$SSHD_CONFIG" << EOF
# CCDC26 Hardened SSH Configuration
# Generated: $(date)

# Network
Port $SSH_PORT
AddressFamily inet
ListenAddress 0.0.0.0

# Protocol
Protocol 2

# Authentication
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Strict mode
StrictModes yes

# Login settings
MaxAuthTries 3
MaxSessions 10
LoginGraceTime 30
# CCDC NOTE: MaxSessions increased to 10 for 8-person teams
ClientAliveInterval 300
ClientAliveCountMax 2

# Security
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no
PermitUserEnvironment no
DisableForwarding yes

# Logging
SyslogFacility AUTH
LogLevel VERBOSE

# Ciphers and algorithms (strong only)
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group14-sha256

# Deny/Allow (uncomment and customize as needed)
# AllowUsers admin operator
# AllowGroups sshusers
# DenyUsers nobody
# DenyGroups nogroup

# Banner
Banner /etc/ssh/banner

# Subsystems
Subsystem sftp /usr/lib/openssh/sftp-server -f AUTHPRIV -l INFO
EOF

    # Create warning banner
    cat > /etc/ssh/banner << 'EOF'
================================================================================
                    AUTHORIZED ACCESS ONLY
================================================================================
This system is for authorized users only. All activities are monitored and 
logged. Unauthorized access attempts will be reported and prosecuted.
================================================================================
EOF

    success "SSH configuration hardened"
    log_action "Hardened SSH configuration"
}

#=============================================================================
# CLEAN AUTHORIZED KEYS
#=============================================================================
audit_authorized_keys() {
    header "Auditing SSH Authorized Keys"
    
    for home in /home/* /root; do
        local auth_keys="$home/.ssh/authorized_keys"
        if [ -f "$auth_keys" ]; then
            local user=$(basename "$home")
            [ "$home" == "/root" ] && user="root"
            
            warn "Found authorized_keys for $user:"
            cat -n "$auth_keys"
            echo
            
            read -p "Clear all keys for $user? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                backup_file "$auth_keys"
                > "$auth_keys"
                success "Cleared authorized_keys for $user"
                log_action "Cleared SSH keys for $user"
            fi
        fi
    done
    
    # Check for keys in unusual locations
    info "Searching for authorized_keys in unusual locations..."
    find / -name "authorized_keys" -o -name "authorized_keys2" 2>/dev/null | while read -r keyfile; do
        case "$keyfile" in
            /home/*/.ssh/authorized_keys|/root/.ssh/authorized_keys)
                # Normal location
                ;;
            *)
                log_finding "Unusual authorized_keys location: $keyfile"
                ;;
        esac
    done
}

#=============================================================================
# CHECK FOR SSH BACKDOORS
#=============================================================================
check_ssh_backdoors() {
    header "Checking for SSH Backdoors"
    
    # Check for PAM backdoors
    info "Checking PAM configuration for SSH..."
    if [ -f /etc/pam.d/sshd ]; then
        grep -v "^#" /etc/pam.d/sshd | grep -v "^$"
        
        # Look for suspicious PAM modules
        if grep -qiE "(pam_permit|pam_succeed|always)" /etc/pam.d/sshd; then
            log_finding "Suspicious PAM module in SSH configuration"
        fi
    fi
    
    # Check SSH binary integrity
    info "Checking SSH binary..."
    local sshd_path=$(which sshd)
    if [ -n "$sshd_path" ]; then
        local sshd_hash=$(hash_file "$sshd_path")
        info "SSHD hash: $sshd_hash"
        
        # Check if it's a symlink to something else
        if [ -L "$sshd_path" ]; then
            warn "SSHD is a symlink: $(readlink -f "$sshd_path")"
        fi
        
        # Check package ownership
        case "$PKG_MGR" in
            apt)
                dpkg -S "$sshd_path" 2>/dev/null || warn "SSHD not owned by any package!"
                ;;
            dnf|yum)
                rpm -qf "$sshd_path" 2>/dev/null || warn "SSHD not owned by any package!"
                ;;
        esac
    fi
    
    # Check for multiple SSH daemons
    info "Checking for multiple SSH daemons..."
    pgrep -a sshd
    
    # Check for SSH on non-standard ports
    info "Checking listening ports..."
    get_listening_ports | grep -i ssh
}

#=============================================================================
# RESTART SSH
#=============================================================================
restart_ssh() {
    header "Restarting SSH Service"
    
    # Test config first
    info "Testing SSH configuration..."
    if sshd -t; then
        success "SSH configuration valid"
        
        # Restart service
        case "$INIT_SYSTEM" in
            systemd)
                systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
                ;;
            openrc)
                rc-service sshd restart 2>/dev/null
                ;;
            sysvinit)
                service ssh restart 2>/dev/null || service sshd restart 2>/dev/null
                ;;
        esac
        
        success "SSH service restarted"
        warn "TEST SSH ACCESS IN NEW TERMINAL BEFORE CLOSING THIS SESSION!"
    else
        error "SSH configuration invalid! Not restarting."
        error "Fix the configuration and try again."
        return 1
    fi
}

#=============================================================================
# QUICK LOCKDOWN (Emergency)
#=============================================================================
emergency_ssh_lockdown() {
    header "EMERGENCY SSH LOCKDOWN"
    warn "This will restrict SSH access severely!"
    
    read -p "Continue with emergency lockdown? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    # Clear all authorized keys
    find /home -name "authorized_keys*" -delete 2>/dev/null
    find /root -name "authorized_keys*" -delete 2>/dev/null
    
    # Disable root login
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
    
    # Reduce max tries
    sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 2/' "$SSHD_CONFIG"
    
    restart_ssh
    
    success "Emergency SSH lockdown complete"
    log_action "Emergency SSH lockdown executed"
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    echo ""
    echo "SSH Hardening Options:"
    echo "1) Audit SSH configuration"
    echo "2) Harden SSHD config"
    echo "3) Audit/clear authorized_keys"
    echo "4) Check for SSH backdoors"
    echo "5) Restart SSH service"
    echo "6) EMERGENCY lockdown"
    echo "7) Run ALL (audit + harden + restart)"
    echo ""
    read -p "Select option [1-7]: " choice
    
    case $choice in
        1) audit_ssh ;;
        2) harden_sshd_config ;;
        3) audit_authorized_keys ;;
        4) check_ssh_backdoors ;;
        5) restart_ssh ;;
        6) emergency_ssh_lockdown ;;
        7)
            audit_ssh
            check_ssh_backdoors
            harden_sshd_config
            audit_authorized_keys
            restart_ssh
            ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
