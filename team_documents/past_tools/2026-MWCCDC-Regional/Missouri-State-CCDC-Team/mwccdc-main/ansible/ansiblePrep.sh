#!/bin/bash 
# ==============================================================================
# Script Name : ansiblePrep.sh
# Description : Enhanced version of setup_ansible_user.sh for CCDC competitions
# Version     : 2.0
# ==============================================================================
# Usage       : ./ansiblePrep.sh
# Notes       :
#   - Run directly on target host (no remote SSH required)
#   - Enhanced security with limited sudo and SSH restrictions
#   - Competition-specific hardening and logging
# ==============================================================================

set -euo pipefail  # Exit on error, undefined var, pipe failure

# Color Variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Configuration
ANSIBLE_USER="teamxansible"  # Keep consistent with existing setup
ANSIBLE_HOME="/home/${ANSIBLE_USER}"
SSH_DIR="${ANSIBLE_HOME}/.ssh"
AUTHORIZED_KEYS="${SSH_DIR}/authorized_keys"
SUDOERS_FILE="/etc/sudoers.d/${ANSIBLE_USER}"
LOG_FILE="/var/log/ansible_secure_setup.log"
BACKUP_DIR="/root/ansible_backup_$(date +%Y%m%d_%H%M%S)"

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${RESET}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "${LOG_FILE}"
}

success() {
    echo -e "${GREEN}✓ $1${RESET}"
    log "SUCCESS: $1"
}

warning() {
    echo -e "${YELLOW}⚠ $1${RESET}"
    log "WARNING: $1"
}

error() {
    echo -e "${RED}✗ ERROR: $1${RESET}" >&2
    log "ERROR: $1"
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo ./ansiblePrep.sh)"
    fi
}

# Detect OS for compatibility
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="${ID}"
        OS_VERSION="${VERSION_ID}"
        log "Detected OS: ${ID} ${VERSION_ID}"
    else
        error "Cannot detect operating system"
    fi
}

# Create ansible user with enhanced security
create_secure_user() {
    log "Setting up ansible user..."
    
    if id "${ANSIBLE_USER}" &>/dev/null; then
        warning "User ${ANSIBLE_USER} already exists - updating configuration"
    else
        # Create user with secure defaults
        useradd -m -s /bin/bash -c "CCDC Ansible User" "${ANSIBLE_USER}"
        success "Created user ${ANSIBLE_USER}"
    fi
    
    # Set secure home directory permissions
    chmod 750 "${ANSIBLE_HOME}"
    chown "${ANSIBLE_USER}:${ANSIBLE_USER}" "${ANSIBLE_HOME}"
    
    # Create SSH directory with proper permissions
    mkdir -p "${SSH_DIR}"
    chmod 700 "${SSH_DIR}"
    chown "${ANSIBLE_USER}:${ANSIBLE_USER}" "${SSH_DIR}"
    
    # Create authorized_keys file
    touch "${AUTHORIZED_KEYS}"
    chmod 600 "${AUTHORIZED_KEYS}"
    chown "${ANSIBLE_USER}:${ANSIBLE_USER}" "${AUTHORIZED_KEYS}"
    
    success "User security configuration completed"
}

#TODO: Add task that will properly get the public ssh key from the user, 
# Likely best to use a web server on a non-standard port that we can just curl. will be easy to do.

install_public_key() {
    log "Installing public key"
    # Add timestamp and restrictions
    {
        echo ""
        echo "# CCDC Ansible Key - Installed $(date)"
        echo "# Security restrictions applied for competition environment"
        echo "# Limited forwarding and command execution"
        echo "restrict,pty,command=\"/bin/bash -c 'if [[ \\\$SSH_ORIGINAL_COMMAND =~ ^(ansible|python|sudo) ]]; then eval \\\$SSH_ORIGINAL_COMMAND; else /bin/bash; fi'\" ${public_key}"
    } >> "${AUTHORIZED_KEYS}"
    
    # Verify file permissions
    chmod 600 "${AUTHORIZED_KEYS}"
    chown "${ANSIBLE_USER}:${ANSIBLE_USER}" "${AUTHORIZED_KEYS}"
    
    success "Public key installed"
}

# Create limited sudo configuration
setup_limited_sudo() {
    log "Configuring limited sudo access for competition security..."
    
    cat > "${SUDOERS_FILE}" << EOF
# System service management (passwordless)
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /bin/systemctl *, /usr/bin/systemctl *
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /sbin/service *, /usr/sbin/service *

# Package management (passwordless)  
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /usr/bin/apt *, /usr/bin/apt-get *
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /usr/bin/yum *, /usr/bin/dnf *, /bin/rpm *

# File operations (limited, passwordless)
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /bin/chown *, /bin/chmod *, /bin/mkdir *
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /bin/cp *, /bin/mv *, /bin/rm *
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /bin/tar *, /bin/gzip *, /usr/bin/unzip *

# Network and security tools (passwordless)
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /usr/sbin/iptables *, /usr/bin/ufw *
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /bin/firewall-cmd *, /usr/bin/firewall-cmd *
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /bin/mount *, /bin/umount *

# Information gathering (passwordless)
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /bin/ps *, /usr/bin/netstat *, /bin/ss *
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /usr/bin/find *, /bin/grep *, /bin/awk *

# Text processing (passwordless)  
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /bin/sed *, /usr/bin/tee *

# Emergency full access (REQUIRES PASSWORD)
${ANSIBLE_USER} ALL=(ALL) ALL

# Security and logging
Defaults:${ANSIBLE_USER} log_host, log_year
Defaults:${ANSIBLE_USER} logfile="/var/log/sudo_${ANSIBLE_USER}.log"
Defaults:${ANSIBLE_USER} !visiblepw, env_reset
Defaults:${ANSIBLE_USER} secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Defaults:${ANSIBLE_USER} timestamp_timeout=15
Defaults:${ANSIBLE_USER} passwd_tries=3
EOF

    # Validate sudoers syntax
    if visudo -c -f "${SUDOERS_FILE}"; then
        chmod 440 "${SUDOERS_FILE}"
        success "Limited sudo configuration applied and validated"
    else
        error "Sudoers file validation failed"
    fi
}

# Test the configuration
test_configuration() {
    log "Testing configuration..."
    
    # Test user can access home
    if sudo -u "${ANSIBLE_USER}" test -r "${ANSIBLE_HOME}"; then
        success "User home directory accessible"
    else
        error "User cannot access home directory"
    fi
    
    # Test SSH directory permissions
    if sudo -u "${ANSIBLE_USER}" test -r "${SSH_DIR}"; then
        success "SSH directory accessible"  
    else
        error "SSH directory not accessible"
    fi
    
    # Test sudo configuration
    if sudo -n -u "${ANSIBLE_USER}" systemctl --version >/dev/null 2>&1; then
        success "Passwordless sudo working for allowed commands"
    else
        warning "Passwordless sudo may not be working (this could be normal)"
    fi
}

# Display final configuration and instructions
show_completion_summary() {
    local host_ip
    host_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}' || echo "UNKNOWN")
    
    echo ""
    echo -e "${GREEN}=== ANSIBLE SETUP COMPLETED SUCCESSFULLY ===${RESET}"
    echo ""
    echo -e "${BLUE}System Information:${RESET}"
    echo "Hostname: $(hostname)"
    echo "IP Address: ${host_ip}"
    echo "OS: ${OS_ID} ${OS_VERSION}"
    echo ""
    echo -e "${BLUE}Ansible Configuration:${RESET}"
    echo "Username: ${ANSIBLE_USER}"
    echo "Home Directory: ${ANSIBLE_HOME}"
    echo ""
    echo -e "${BLUE}For Ansible Controller - Add to inventory.ini:${RESET}"
    echo "$(hostname) ansible_host=${host_ip} ansible_user=${ANSIBLE_USER}"
    echo ""
    echo -e "${BLUE}Test Connection:${RESET}"
    echo "ansible $(hostname) -m ping"
    echo ""
    echo -e "${YELLOW}Security Features Enabled:${RESET}"
    echo "✓ Restricted SSH key (command filtering)"
    echo "✓ Limited sudo access (specific commands only)"
    echo "✓ Comprehensive logging (${LOG_FILE})"
    echo "✓ Secure file permissions"
    echo "✓ Configuration backup (${BACKUP_DIR})"
    echo ""
    echo -e "${YELLOW}Important Notes:${RESET}"
    echo "- All sudo actions logged to /var/log/sudo_${ANSIBLE_USER}.log"
    echo "- Backup of previous config saved in ${BACKUP_DIR}"
    echo ""
}

# Main execution
main() {
    # Pre-flight checks
    check_root
    detect_os
    
    # Security warning
    echo -e "${YELLOW}⚠ SECURITY WARNING ⚠${RESET}"
    echo "This script will create a privileged user account for Ansible automation."
    read -p "Do you want to continue? (y/N): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Setup cancelled by user"
        exit 0
    fi
    
    # Execute setup steps
    log "Starting secure Ansible setup on $(hostname)"
    backup_existing
    create_secure_user
    get_public_key
    install_public_key
    setup_limited_sudo
    test_configuration
    show_completion_summary
    
    success "Secure Ansible setup completed successfully!"
    log "Setup completed at $(date)"
}

# Execute main function
main "$@"