#!/bin/bash
#=============================================================================
# CCDC26 All-in-One Deployment Script
#=============================================================================
# Master entry point for the CCDC26 toolkit
# Detects environment and provides appropriate options
#
# Usage:
#   ./deploy.sh              # Interactive menu
#   ./deploy.sh --quick      # Quick local harden
#   ./deploy.sh --ansible    # Ansible deployment menu
#=============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#=============================================================================
# COLORS
#=============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
header()  { echo -e "\n${BOLD}${PURPLE}=== $1 ===${NC}\n"; }

#=============================================================================
# ENVIRONMENT DETECTION
#=============================================================================
detect_environment() {
    # Check if we're on the target system or an Ansible controller
    IS_ANSIBLE_CONTROLLER=false
    IS_TARGET_SYSTEM=true
    
    # Check for Ansible (may be in user's ~/.local/bin from pip install)
    if command -v ansible &>/dev/null; then
        IS_ANSIBLE_CONTROLLER=true
    elif [ -f "$HOME/.local/bin/ansible" ]; then
        IS_ANSIBLE_CONTROLLER=true
        export PATH="$HOME/.local/bin:$PATH"
    elif [ -f "/home/$SUDO_USER/.local/bin/ansible" ] 2>/dev/null; then
        # Running as sudo, check the original user's pip install location
        IS_ANSIBLE_CONTROLLER=true
        export PATH="/home/$SUDO_USER/.local/bin:$PATH"
    elif python3 -c "import ansible" &>/dev/null; then
        IS_ANSIBLE_CONTROLLER=true
    fi
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="$NAME"
        OS_ID="$ID"
    else
        OS_NAME="Unknown"
        OS_ID="unknown"
    fi
    
    # Check if root
    IS_ROOT=false
    if [ "$EUID" -eq 0 ]; then
        IS_ROOT=true
    fi
}

#=============================================================================
# BANNER
#=============================================================================
show_banner() {
    echo -e "${CYAN}"
    echo "  ██████╗ ██████╗██████╗  ██████╗██████╗  ██████╗ "
    echo " ██╔════╝██╔════╝██╔══██╗██╔════╝╚════██╗██╔════╝ "
    echo " ██║     ██║     ██║  ██║██║      █████╔╝███████╗ "
    echo " ██║     ██║     ██║  ██║██║     ██╔═══╝ ██╔═══██╗"
    echo " ╚██████╗╚██████╗██████╔╝╚██████╗███████╗╚██████╔╝"
    echo "  ╚═════╝ ╚═════╝╚═════╝  ╚═════╝╚══════╝ ╚═════╝ "
    echo -e "${NC}"
    echo -e "${BOLD}CCDC26 Defense Toolkit${NC}"
    echo ""
    echo -e "OS: ${GREEN}$OS_NAME${NC}"
    echo -e "Ansible: ${GREEN}$([ "$IS_ANSIBLE_CONTROLLER" = true ] && echo "Available" || echo "Not installed")${NC}"
    echo -e "Root: ${GREEN}$([ "$IS_ROOT" = true ] && echo "Yes" || echo "No")${NC}"
    echo ""
}

#=============================================================================
# QUICK HARDEN (non-interactive)
#=============================================================================
quick_harden() {
    if [ "$IS_ROOT" != true ]; then
        error "Must be root. Run: sudo $0"
        exit 1
    fi
    
    header "Quick Harden - Starting"
    info "This will harden the system with safe defaults."
    info "Passwords are NOT changed - use Ansible for that."
    echo ""
    
    cd "$SCRIPT_DIR/linux-scripts"
    bash ./hardening/full-harden.sh
    
    success "Quick Harden complete!"
}

#=============================================================================
# ADVANCED MENU (for power users)
#=============================================================================
advanced_menu() {
    header "Advanced Options"
    
    echo -e "${YELLOW}All options affect THIS machine only.${NC}"
    echo ""
    echo "Hardening:"
    echo "  1) Interactive Harden     - Choose individual scripts (users, ssh, firewall, etc.)"
    echo "  2) Service Hardening      - Harden specific services (web, mail, DNS)"
    echo ""
    echo "SIEM/Monitoring:"
    echo "  3) Deploy Splunk Forwarder- Install Splunk forwarder on THIS machine"
    echo "  4) Start Monitoring       - Real-time file/process/network monitoring"
    echo ""
    echo "Security:"
    echo "  5) Hunt for Persistence   - Scan for backdoors, cron jobs, startup scripts"
    echo "  6) Incident Response      - Evidence collection, session killing, isolation"
    echo "  7) User Enumeration       - List users, permissions, sudo access, SSH keys"
    echo ""
    echo "0) Back to main menu"
    echo ""
    
    read -p "Select option: " choice
    
    case $choice in
        1)
            if [ "$IS_ROOT" != true ]; then
                error "Must be root. Run: sudo $0"
                return
            fi
            header "Interactive Hardening"
            cd "$SCRIPT_DIR/linux-scripts/hardening"
            echo "Available hardening scripts:"
            echo "  1) users.sh     - User account hardening"
            echo "  2) ssh.sh       - SSH hardening"
            echo "  3) firewall.sh  - Firewall setup"
            echo "  4) services.sh  - Service management"
            echo "  5) permissions.sh - File permissions"
            echo "  6) kernel.sh    - Kernel hardening"
            echo ""
            read -p "Select script [1-6]: " script_choice
            case $script_choice in
                1) bash ./users.sh ;;
                2) bash ./ssh.sh ;;
                3) bash ./firewall.sh ;;
                4) bash ./services.sh ;;
                5) bash ./permissions.sh ;;
                6) bash ./kernel.sh ;;
                *) error "Invalid option" ;;
            esac
            ;;
        2)
            if [ "$IS_ROOT" != true ]; then
                error "Must be root. Run: sudo $0"
                return
            fi
            header "Running Service Hardening"
            cd "$SCRIPT_DIR/linux-scripts/services"
            bash ./harden-all.sh
            ;;
        3)
            if [ "$IS_ROOT" != true ]; then
                error "Must be root. Run: sudo $0"
                return
            fi
            header "Deploying Splunk Forwarder"
            info "Forwarding to competition Splunk server: 172.20.242.20:9997"
            cd "$SCRIPT_DIR/linux-scripts/tools"
            bash ./splunk-forwarder.sh
            ;;
        4)
            if [ "$IS_ROOT" != true ]; then
                error "Must be root. Run: sudo $0"
                return
            fi
            header "Starting Monitoring"
            cd "$SCRIPT_DIR/linux-scripts/monitoring"
            bash ./deploy-monitoring.sh
            ;;
        5)
            if [ "$IS_ROOT" != true ]; then
                error "Must be root. Run: sudo $0"
                return
            fi
            header "Hunting for Persistence"
            cd "$SCRIPT_DIR/linux-scripts/persistence-hunting"
            bash ./full-hunt.sh
            ;;
        6)
            if [ "$IS_ROOT" != true ]; then
                error "Must be root. Run: sudo $0"
                return
            fi
            header "Incident Response Tools"
            cd "$SCRIPT_DIR/linux-scripts/incident-response"
            echo "Available IR scripts:"
            ls -1 *.sh
            echo ""
            read -p "Enter script name (or 'back'): " ir_script
            if [ "$ir_script" != "back" ] && [ -f "$ir_script" ]; then
                bash "./$ir_script"
            fi
            ;;
        7)
            if [ "$IS_ROOT" != true ]; then
                error "Must be root. Run: sudo $0"
                return
            fi
            header "User Enumeration"
            cd "$SCRIPT_DIR/linux-scripts/persistence-hunting"
            bash ./user-audit.sh
            ;;
        0)
            return
            ;;
        *)
            error "Invalid option"
            ;;
    esac
}

#=============================================================================
# ANSIBLE MENU
#=============================================================================

# Global ansible settings
ANSIBLE_AUTH_MODE="prompt"  # "prompt" = ask for passwords, "inventory" = use inventory file
ANSIBLE_EXTRA_ARGS=""

setup_ansible_auth() {
    header "Ansible Authentication Setup"
    echo "How do you want to authenticate to remote hosts?"
    echo ""
    echo "  1) Prompt for passwords (RECOMMENDED - more secure)"
    echo "     Will ask for SSH password and sudo password at runtime"
    echo ""
    echo "  2) Use inventory file credentials (faster, less secure)"
    echo "     Uses ansible_password and ansible_become_pass from inventory.ini"
    echo ""
    read -p "Select [1-2] (default: 1): " auth_choice
    
    case $auth_choice in
        2)
            ANSIBLE_AUTH_MODE="inventory"
            ANSIBLE_EXTRA_ARGS=""
            info "Using inventory file credentials"
            ;;
        *)
            ANSIBLE_AUTH_MODE="prompt"
            ANSIBLE_EXTRA_ARGS="--ask-pass --ask-become-pass"
            info "Will prompt for SSH and sudo passwords"
            ;;
    esac
    
    # Always disable host key checking for CCDC speed
    export ANSIBLE_HOST_KEY_CHECKING=False
    success "Host key checking disabled"
    echo ""
}

ansible_menu() {
    if [ "$IS_ANSIBLE_CONTROLLER" != true ]; then
        error "Ansible is not installed"
        echo "Install with: pip3 install ansible pywinrm"
        return
    fi
    
    # Check for optional but recommended dependencies
    local missing_deps=()
    if ! command -v sshpass &>/dev/null; then
        missing_deps+=("sshpass (required for password-based SSH)")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        warn "Optional dependencies missing:"
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        echo ""
        if [ "$OS_ID" = "ubuntu" ] || [ "$OS_ID" = "debian" ]; then
            echo "Install with: sudo apt install -y sshpass"
        elif [ "$OS_ID" = "fedora" ] || [ "$OS_ID" = "rhel" ]; then
            echo "Install with: sudo dnf install -y sshpass"
        fi
        echo ""
        info "Continuing anyway (you may need these for some features)..."
        echo ""
    fi
    
    # Setup auth on first run
    if [ -z "$ANSIBLE_AUTH_CONFIGURED" ]; then
        setup_ansible_auth
        ANSIBLE_AUTH_CONFIGURED=true
    fi
    
    header "Ansible Control Panel"
    
    echo -e "${YELLOW}These commands run on OTHER machines listed in ansible/inventory.ini${NC}"
    echo -e "${YELLOW}This machine is the controller - it sends commands via SSH/WinRM.${NC}"
    echo -e "Auth mode: ${GREEN}$ANSIBLE_AUTH_MODE${NC} | Extra args: ${GREEN}${ANSIBLE_EXTRA_ARGS:-none}${NC}"
    echo ""
    echo "1) Generate inventory from CSV     - Convert CSV to inventory.ini"
    echo "2) Test connectivity               - Verify Ansible can reach all machines (run first!)"
    echo "3) Password Reset + Kick Sessions  - Change ALL passwords, create ccdcuser1/2, boot attackers"
    echo "4) Deploy Hardening Scripts        - Copy toolkit to all machines (option to run)"
    echo "5) Deploy Splunk Forwarders        - Install Splunk forwarder on all machines"
    echo "6) Gather Facts                    - Collect system info from all machines"
    echo "7) Run custom playbook"
    echo "8) Change auth mode                - Switch between prompt/inventory auth"
    echo ""
    echo "0) Back to main menu"
    echo ""
    
    read -p "Select option: " choice
    
    ANSIBLE_DIR="$SCRIPT_DIR/ansible"
    
    case $choice in
        1)
            header "Generate Inventory from CSV"
            read -p "Enter path to CSV file: " csv_file
            if [ -f "$csv_file" ]; then
                python3 "$ANSIBLE_DIR/setup/csv2inv.py" "$csv_file" "$ANSIBLE_DIR/inventory.ini"
                success "Inventory generated: $ANSIBLE_DIR/inventory.ini"
            else
                error "File not found: $csv_file"
            fi
            ;;
        2)
            header "Testing Connectivity"
            
            # Check for sshpass if using prompt auth mode
            if [ "$ANSIBLE_AUTH_MODE" = "prompt" ]; then
                if ! command -v sshpass &>/dev/null; then
                    error "sshpass is required for password-based authentication"
                    echo ""
                    echo "Install with:"
                    if [ "$OS_ID" = "ubuntu" ] || [ "$OS_ID" = "debian" ]; then
                        echo "  sudo apt install -y sshpass"
                    elif [ "$OS_ID" = "fedora" ] || [ "$OS_ID" = "rhel" ]; then
                        echo "  sudo dnf install -y sshpass"
                    else
                        echo "  sudo apt install -y sshpass  # Debian/Ubuntu"
                        echo "  sudo dnf install -y sshpass  # Fedora/RHEL"
                    fi
                    echo ""
                    read -p "Press Enter to continue..."
                    return
                fi
            fi
            
            info "Testing connectivity to all hosts..."
            info "Using auth mode: $ANSIBLE_AUTH_MODE"
            echo ""
            
            # Run connectivity test
            if ansible all -i "$ANSIBLE_DIR/inventory.ini" -m ping $ANSIBLE_EXTRA_ARGS; then
                echo ""
                success "All hosts reachable!"
            else
                echo ""
                warn "Some hosts failed. Check inventory.ini passwords and SSH connectivity."
                echo ""
                echo "Common issues:"
                echo "  - Wrong password in inventory.ini"
                echo "  - SSH not enabled on target"
                echo "  - Firewall blocking SSH/WinRM"
                echo "  - Network routing issues"
            fi
            
            echo ""
            read -p "Press Enter to continue..."
            ;;
        3)
            header "Password Reset and User Creation"
            warn "This will reset ALL user passwords and create competition users!"
            read -p "Continue? (y/n): " confirm
            if [ "$confirm" = "y" ]; then
                ansible-playbook -i "$ANSIBLE_DIR/inventory.ini" "$ANSIBLE_DIR/changepw_kick.yml" $ANSIBLE_EXTRA_ARGS
            fi
            ;;
        4)
            header "Deploy Hardening Scripts"
            echo "Options:"
            echo "  1) Deploy only (no execution)"
            echo "  2) Deploy and run full hardening"
            echo ""
            read -p "Select [1-2]: " deploy_opt
            
            case $deploy_opt in
                1)
                    ansible-playbook -i "$ANSIBLE_DIR/inventory.ini" "$ANSIBLE_DIR/deploy_hardening.yml" $ANSIBLE_EXTRA_ARGS
                    ;;
                2)
                    ansible-playbook -i "$ANSIBLE_DIR/inventory.ini" "$ANSIBLE_DIR/deploy_hardening.yml" -e "run_full=true" $ANSIBLE_EXTRA_ARGS
                    ;;
            esac
            ;;
        5)
            header "Deploy Splunk Forwarders"
            info "Forwarding to competition Splunk server: 172.20.242.20:9997"
            ansible-playbook -i "$ANSIBLE_DIR/inventory.ini" "$ANSIBLE_DIR/deploy_splunk_forwarders.yml" $ANSIBLE_EXTRA_ARGS
            ;;
        6)
            header "Gathering Facts"
            ansible-playbook -i "$ANSIBLE_DIR/inventory.ini" "$ANSIBLE_DIR/gather_facts.yml" $ANSIBLE_EXTRA_ARGS
            success "Facts saved to: $ANSIBLE_DIR/collected_facts/"
            ;;
        7)
            header "Run Custom Playbook"
            read -p "Enter playbook path: " playbook
            if [ -f "$playbook" ]; then
                ansible-playbook -i "$ANSIBLE_DIR/inventory.ini" "$playbook" $ANSIBLE_EXTRA_ARGS
            else
                error "Playbook not found: $playbook"
            fi
            ;;
        8)
            ANSIBLE_AUTH_CONFIGURED=""
            setup_ansible_auth
            ANSIBLE_AUTH_CONFIGURED=true
            ;;
        0)
            return
            ;;
        *)
            error "Invalid option"
            ;;
    esac
}

#=============================================================================
# MAIN MENU (Simple 3-option menu)
#=============================================================================
main_menu() {
    while true; do
        show_banner
        
        echo -e "${YELLOW}Options 1 & 3 affect THIS machine. Option 2 affects OTHER machines.${NC}"
        echo ""
        echo "1) Quick Harden (this machine) - SSH, firewall, services, kernel. No passwords."
        if [ "$IS_ANSIBLE_CONTROLLER" = true ]; then
            echo "2) Ansible Control Panel     - Manage all machines remotely"
        else
            echo "2) Ansible Control Panel     - (not available - pip3 install ansible pywinrm)"
        fi
        echo "3) Advanced Options          - Individual tools, SIEM agents, IR"
        echo ""
        echo "q) Quit"
        echo ""
        
        read -p "Select option: " choice
        
        case $choice in
            1)
                quick_harden
                ;;
            2)
                ansible_menu
                ;;
            3)
                advanced_menu
                ;;
            q|Q)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                error "Invalid option"
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
        clear
    done
}

#=============================================================================
# COMMAND LINE OPTIONS
#=============================================================================
case "${1:-}" in
    --quick|-q)
        detect_environment
        quick_harden
        exit 0
        ;;
    --ansible|-a)
        detect_environment
        ansible_menu
        exit 0
        ;;
    --help|-h)
        echo "CCDC26 Toolkit"
        echo ""
        echo "Usage: sudo $0 [option]"
        echo ""
        echo "OPTIONS:"
        echo "  (none)      Interactive menu"
        echo "  --quick     Quick harden THIS machine (no passwords changed)"
        echo "  --ansible   Jump to Ansible menu (manage OTHER machines)"
        echo "  --help      Show this help"
        echo ""
        echo "MAIN MENU OPTIONS:"
        echo "  1) Quick Harden    - Hardens THIS machine only"
        echo "                       Does: SSH, firewall, services, permissions, kernel"
        echo "                       Does NOT: Change passwords"
        echo "                       Time: ~2 minutes"
        echo ""
        echo "  2) Ansible Panel   - Manage OTHER machines via SSH/WinRM"
        echo "                       Requires: pip3 install ansible pywinrm"
        echo "                       Key options:"
        echo "                         3) Password Reset - Changes ALL passwords everywhere"
        echo "                         4) Deploy Hardening - Copies+runs scripts on all machines"
        echo ""
        echo "  3) Advanced        - Individual tools for THIS machine"
        echo "                       SIEM agents, persistence hunting, IR tools"
        echo ""
        echo "TYPICAL WORKFLOW:"
        echo "  1. sudo ./deploy.sh → 2 → 2  (Test Ansible connectivity)"
        echo "  2. sudo ./deploy.sh → 2 → 3  (Change all passwords)"
        echo "  3. sudo ./deploy.sh → 1      (Harden this machine)"
        echo "  4. sudo ./deploy.sh → 2 → 4  (Harden all other machines)"
        echo ""
        echo "See QUICKREF.md for full documentation."
        exit 0
        ;;
esac

# Default: interactive menu
detect_environment
clear
main_menu
