#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Full System Hardening
# Run all hardening scripts in recommended order
# NOTE: This script does NOT change passwords - use Ansible for that

source "$(dirname "$0")/../utils/common.sh"
require_root

SCRIPT_DIR="$(dirname "$0")"

header "CCDC26 Full System Hardening"

info "This will harden the system with safe defaults."
info "Passwords are NOT changed here - use Ansible changepw_kick.yml for that."
warn "Make sure you have console access in case SSH breaks!"
echo ""

# Record start time
START_TIME=$(date +%s)

#=============================================================================
# Phase 1: User Account Hardening (NO password changes)
#=============================================================================
header "Phase 1: User Account Hardening"
info "Auditing and securing user accounts (passwords NOT changed)..."

# Source users.sh to get functions
source "$SCRIPT_DIR/users.sh"

# Run user hardening WITHOUT password changes
audit_users
harden_sudo
set_password_policy

# Note: disable_unauthorized_users is interactive, skip in quick mode
# Users can run it manually from Advanced Options if needed

#=============================================================================
# Phase 2: SSH Hardening
#=============================================================================
header "Phase 2: SSH Hardening"
info "Securing SSH configuration..."
bash "$SCRIPT_DIR/ssh.sh" <<< "7"

#=============================================================================
# Phase 3: Firewall Configuration
#=============================================================================
header "Phase 3: Firewall Configuration"
info "Setting up firewall rules..."
info "Detecting running services to avoid blocking scored services..."

# Source firewall.sh to get detected ports
source "$SCRIPT_DIR/firewall.sh" 2>/dev/null || true

echo ""
warn "Firewall will allow these TCP ports: ${ALLOWED_TCP_PORTS:-22 80 443}"
warn "Firewall will allow these UDP ports: ${ALLOWED_UDP_PORTS:-none}"
echo ""
read -p "Proceed with these ports? (y to continue, n to skip firewall): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash "$SCRIPT_DIR/firewall.sh" <<< "2"
else
    warn "Skipping firewall configuration - configure manually!"
fi

#=============================================================================
# Phase 4: Service Management
#=============================================================================
header "Phase 4: Service Management"
info "Disabling dangerous services..."
bash "$SCRIPT_DIR/services.sh" <<< "7"

#=============================================================================
# Phase 5: File Permissions
#=============================================================================
header "Phase 5: File Permissions"
info "Fixing file permissions..."
bash "$SCRIPT_DIR/permissions.sh" <<< "10"

#=============================================================================
# Phase 6: Kernel Hardening
#=============================================================================
header "Phase 6: Kernel Hardening"
info "Applying kernel security parameters..."
bash "$SCRIPT_DIR/kernel.sh" <<< "5"

#=============================================================================
# Complete
#=============================================================================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

header "Hardening Complete"
success "Full hardening completed in $DURATION seconds"

echo ""
echo "NEXT STEPS:"
echo "1. Change passwords via Ansible: ansible-playbook changepw_kick.yml"
echo "2. Test SSH access in a NEW terminal before closing this one"
echo "3. Verify critical services are running"
echo "4. Check firewall allows required ports"
echo "5. Review /var/log/ccdc-toolkit/ for findings"
echo "6. Run persistence hunting: ../persistence-hunting/full-hunt.sh"
echo ""

log_action "Full system hardening completed"
