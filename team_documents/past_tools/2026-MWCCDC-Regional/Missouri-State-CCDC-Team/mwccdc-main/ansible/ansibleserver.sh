#!/bin/bash
# ==============================================================================
# Script Name : ansibleserver.sh
# Description : Enhanced Ansible Server Setup for CCDC Competition
#               Sets up Ansible controller with secure key generation and distribution
# Author      : Tyler Olson (Enhanced by Missouri State CCDC Team)
# Organization: Missouri State University
# Version     : 2.0
# ==============================================================================
# Usage       : ./ansibleserver.sh
# Notes       :
#   - Sets up Ansible controller with all dependencies
#   - Generates secure SSH keys for competition use
#   - Creates and hosts the public key on a temporary web server queried during
#     ansiblePrep.sh script.
#   - Downloads CIS audit and remediation repositories
# ==============================================================================

set -e

# Steps for ubuntu on 2019 docker:
# 1. Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
# 2. Invoke-WebRequest -Uri https://aka.ms/wslubuntu2004 -OutFile Ubuntu.appx -UseBasicParsing
# Here for rest: https://learn.microsoft.com/en-us/windows/wsl/install-on-server

# Color Variables
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RESET='\033[0m'

# Configuration
TEAM_KEY="ccdc_ansible_key"
SSH_DIR="$HOME/.ssh"
KEY_DIST_DIR="$HOME/ansible/key_distribution"

log() {
    echo -e "${RED}$1${RESET}"
}

success() {
    echo -e "${GREEN}✓ $1${RESET}"
}

info() {
    echo -e "${BLUE}ℹ $1${RESET}"
}

pre-setup() {
    # Update the server and install the required packages
    sudo apt update
    sudo apt install ansible python3-paramiko git -y

    # make the directory for ansible 
    mkdir ~/ansible && cd ~/ansible || log "failed to change directory"

    # Take the hosts file in the given files and send it to /etc/hosts
    cat hosts | sudo tee -a /etc/hosts || log "Failed to put the hosts file in"
}

galaxy-setup() {
    ansible-galaxy install -r requirements.yml || log "Failed to install the requirements" 
}


github() {
    mkdir ~/ansible/github && cd ~/ansible/github || log "Failed to Change Directory"
    # Audit for CIS configurations
    git clone https://github.com/ansible-lockdown/Windows-2019-CIS-Audit
    git clone https://github.com/ansible-lockdown/RHEL7-CIS-Audit
    git clone https://github.com/ansible-lockdown/UBUNTU18-CIS-Audit 

    # Remediate to CIS Benchmarks 
    git clone https://github.com/ansible-lockdown/Windows-2019-CIS
    git clone https://github.com/rdiers/CentOS7-CIS 
    git clone https://github.com/ansible-lockdown/RHEL7-CIS
    git clone https://github.com/ansible-lockdown/UBUNTU18-CIS 

    #reset to home
    cd ~
}


git_sparse_clone() (
  rurl="$1" localdir="$2" && shift 2

  mkdir -p "$localdir"
  cd "$localdir"

  git init
  git remote add -f origin "$rurl"

  git config core.sparseCheckout true

  # Loops over remaining args
  for i; do
    echo "$i" >> .git/info/sparse-checkout
  done

  git pull origin master
)


# Generate SSH keys for CCDC (secure for competition)
generate_ccdc_keys() {
    info "Generating CCDC Ansible SSH keys..."
    
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    
    local key_path="${SSH_DIR}/${TEAM_KEY}"
    
    if [[ -f "$key_path" ]]; then
        echo -e "${YELLOW}SSH key already exists: $key_path${RESET}"
        read -p "Regenerate key for this competition? (y/N): " regen
        if [[ "$regen" != "y" && "$regen" != "Y" ]]; then
            info "Using existing key"
            return 0
        fi
    fi
    
    # Generate ED25519 key (more secure, shorter)
    ssh-keygen -t ed25519 -f "$key_path" -C "mwccdc_ansible_$(date +%Y%m%d)" -N ""
    chmod 600 "$key_path"
    chmod 644 "${key_path}.pub"
    
    success "SSH key pair generated"
    
    # Update inventory to use new key
    if [[ -f "inventory.ini" ]]; then
        sed -i.backup "s|ansible_ssh_private_key_file=.*|ansible_ssh_private_key_file=${key_path}|g" inventory.ini
        success "Updated inventory.ini with new key path"
    fi
}

#TODO: Add proper implementation of web server key distrobution to hosts. 
#TODO: HACK THE PLANET!!!!

# Display team instructions
show_team_workflow() {
    local pub_key_path="${SSH_DIR}/${TEAM_KEY}.pub"
    
    echo ""
    echo -e "${GREEN}=== CCDC ANSIBLE CONTROLLER READY ===${RESET}"
    echo ""
    echo -e "${BLUE}Team Workflow:${RESET}"
    echo ""
    echo -e "${YELLOW}1. For Hardening Team Members:${RESET}"
    echo "   • Copy ansiblePrep.sh to target Linux hosts"
    echo "   • Run: sudo ./ansiblePrep.sh"
    echo "   • Provide public key when prompted (see methods below)"
    echo -e "${BLUE}Public Key Distribution:${RESET}"
    if [[ -f "$pub_key_path" ]]; then
        echo "Show key: cat $pub_key_path"
        echo "Base64:   cat ${KEY_DIST_DIR}/public_key_base64.txt"
        echo "Verify:   cat ${KEY_DIST_DIR}/key_verification.txt"
    fi
    echo ""
    echo -e "${BLUE}Files created:${RESET}"
    echo "SSH Key: ${SSH_DIR}/${TEAM_KEY}"
    echo "Distribution: $KEY_DIST_DIR"
    echo "Hardening Script: Linux/ansiblePrep.sh"
}

main() {
    echo -e "${BLUE}=== CCDC Ansible Controller Setup ===${RESET}"
    echo "Setting up Ansible server with enhanced security for competition"
    echo ""
    
    pre-setup || log "Pre-setup failed"
    galaxy-setup || log "Galaxy setup failed" 
    generate_ccdc_keys || log "Key generation failed"
    create_key_distribution || log "Key distribution setup failed"
    github || log "GitHub repositories failed"
    git_sparse_clone "https://github.com/Missouri-State-CCDC-Team/mwccdc" "./ansible/" "/ansible"
    show_team_workflow
    
    success "CCDC Ansible controller setup complete!"
}

main "$@"