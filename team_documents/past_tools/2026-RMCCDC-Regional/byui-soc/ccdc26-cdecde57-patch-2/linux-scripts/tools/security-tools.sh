#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Security Tools Setup
# Install useful security and monitoring tools

source "$(dirname "$0")/../utils/common.sh"
require_root

header "Security Tools Setup"

#=============================================================================
# TOOL CATEGORIES
#=============================================================================
MONITORING_TOOLS="htop iotop iftop nethogs nload bmon"
NETWORK_TOOLS="nmap tcpdump wireshark-cli netcat-openbsd socat"
FORENSIC_TOOLS="lsof strace ltrace"
FILE_TOOLS="aide tripwire rkhunter chkrootkit lynis"
LOG_TOOLS="logwatch sysstat auditd"
SECURITY_TOOLS="fail2ban ufw clamav"

#=============================================================================
# INSTALL ESSENTIAL TOOLS
#=============================================================================
install_essential() {
    header "Installing Essential Tools"
    
    local tools=""
    
    case "$PKG_MGR" in
        apt)
            apt-get update
            tools="htop iotop iftop lsof strace net-tools iproute2 tcpdump nmap curl wget vim nano tree psmisc procps sysstat auditd"
            apt-get install -y $tools
            ;;
        dnf|yum)
            tools="htop iotop iftop lsof strace net-tools iproute tcpdump nmap curl wget vim nano tree psmisc procps-ng sysstat audit"
            $PKG_MGR install -y $tools
            ;;
        apk)
            tools="htop iotop iftop lsof strace net-tools iproute2 tcpdump nmap curl wget vim nano tree psmisc procps"
            apk add $tools
            ;;
        pacman)
            tools="htop iotop iftop lsof strace net-tools iproute2 tcpdump nmap curl wget vim nano tree psmisc procps-ng sysstat audit"
            pacman -S --noconfirm $tools
            ;;
    esac
    
    success "Essential tools installed"
}

#=============================================================================
# INSTALL AUDITD
#=============================================================================
install_auditd() {
    header "Installing and Configuring Auditd"
    
    case "$PKG_MGR" in
        apt) apt-get install -y auditd audispd-plugins ;;
        dnf|yum) $PKG_MGR install -y audit audit-libs ;;
        pacman) pacman -S --noconfirm audit ;;
    esac
    
    # Configure audit rules
    cat > /etc/audit/rules.d/ccdc.rules << 'EOF'
# CCDC Audit Rules

# Delete all existing rules
-D

# Buffer size
-b 8192

# Failure mode (1=printk, 2=panic)
-f 1

# Monitor authentication
-w /etc/passwd -p wa -k passwd_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/group -p wa -k group_changes
-w /etc/gshadow -p wa -k gshadow_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/sudoers.d/ -p wa -k sudoers_changes

# Monitor SSH
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /root/.ssh/ -p wa -k root_ssh

# Monitor cron
-w /etc/crontab -p wa -k cron
-w /etc/cron.d/ -p wa -k cron
-w /var/spool/cron/ -p wa -k cron

# Monitor systemd
-w /etc/systemd/system/ -p wa -k systemd
-w /lib/systemd/system/ -p wa -k systemd

# Monitor network config
-w /etc/hosts -p wa -k hosts
-w /etc/network/ -p wa -k network
-w /etc/sysconfig/network-scripts/ -p wa -k network

# Monitor privilege escalation
-a always,exit -F arch=b64 -S setuid -S setgid -S setreuid -S setregid -k privilege_escalation
-a always,exit -F arch=b32 -S setuid -S setgid -S setreuid -S setregid -k privilege_escalation

# Monitor process execution
-a always,exit -F arch=b64 -S execve -k exec
-a always,exit -F arch=b32 -S execve -k exec

# Monitor file deletion
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -k delete
-a always,exit -F arch=b32 -S unlink -S unlinkat -S rename -S renameat -k delete

# Monitor module loading
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules

# Make config immutable (must be last)
-e 2
EOF

    # Load rules
    augenrules --load 2>/dev/null || auditctl -R /etc/audit/rules.d/ccdc.rules
    
    # Start service
    service_start auditd
    
    success "Auditd configured"
    log_action "Installed and configured auditd"
}

#=============================================================================
# INSTALL RKHUNTER
#=============================================================================
install_rkhunter() {
    header "Installing Rootkit Hunter"
    
    case "$PKG_MGR" in
        apt) apt-get install -y rkhunter ;;
        dnf|yum) $PKG_MGR install -y rkhunter ;;
        pacman) pacman -S --noconfirm rkhunter ;;
        apk) apk add rkhunter ;;
    esac
    
    if command -v rkhunter &>/dev/null; then
        # Update database
        rkhunter --update 2>/dev/null
        rkhunter --propupd 2>/dev/null
        
        success "Rootkit Hunter installed"
        info "Run 'rkhunter --check' to scan for rootkits"
    else
        error "Failed to install rkhunter"
    fi
}

#=============================================================================
# INSTALL CHKROOTKIT
#=============================================================================
install_chkrootkit() {
    header "Installing Chkrootkit"
    
    case "$PKG_MGR" in
        apt) apt-get install -y chkrootkit ;;
        dnf|yum) $PKG_MGR install -y chkrootkit ;;
        pacman) pacman -S --noconfirm chkrootkit ;;
    esac
    
    if command -v chkrootkit &>/dev/null; then
        success "Chkrootkit installed"
        info "Run 'chkrootkit' to scan for rootkits"
    fi
}

#=============================================================================
# INSTALL LYNIS
#=============================================================================
install_lynis() {
    header "Installing Lynis Security Auditor"
    
    case "$PKG_MGR" in
        apt) apt-get install -y lynis ;;
        dnf|yum) $PKG_MGR install -y lynis ;;
        pacman) pacman -S --noconfirm lynis ;;
    esac
    
    if command -v lynis &>/dev/null; then
        success "Lynis installed"
        info "Run 'lynis audit system' for security audit"
    else
        # Try installing from git
        if command -v git &>/dev/null; then
            git clone https://github.com/CISOfy/lynis /opt/lynis 2>/dev/null
            if [ -f /opt/lynis/lynis ]; then
                ln -sf /opt/lynis/lynis /usr/local/bin/lynis
                success "Lynis installed from git"
            fi
        fi
    fi
}

#=============================================================================
# INSTALL CLAMAV
#=============================================================================
install_clamav() {
    header "Installing ClamAV Antivirus"
    
    case "$PKG_MGR" in
        apt) apt-get install -y clamav clamav-daemon ;;
        dnf|yum) $PKG_MGR install -y clamav clamav-update clamd ;;
        pacman) pacman -S --noconfirm clamav ;;
        apk) apk add clamav ;;
    esac
    
    if command -v clamscan &>/dev/null; then
        # Update virus definitions
        info "Updating virus definitions..."
        systemctl stop clamav-freshclam 2>/dev/null
        freshclam 2>/dev/null
        
        success "ClamAV installed"
        info "Run 'clamscan -r /path' to scan for malware"
    fi
}

#=============================================================================
# INSTALL AIDE
#=============================================================================
install_aide() {
    header "Installing AIDE (File Integrity)"
    
    case "$PKG_MGR" in
        apt) apt-get install -y aide ;;
        dnf|yum) $PKG_MGR install -y aide ;;
        pacman) pacman -S --noconfirm aide ;;
    esac
    
    if command -v aide &>/dev/null; then
        info "Initializing AIDE database (this takes a while)..."
        aide --init 2>/dev/null &
        
        success "AIDE installed"
        info "Database initializing in background"
        info "Run 'aide --check' after init completes"
    fi
}

#=============================================================================
# RUN SECURITY SCAN
#=============================================================================
run_security_scan() {
    header "Running Security Scans"
    
    local scan_dir="/tmp/security-scan-$(timestamp)"
    mkdir -p "$scan_dir"
    
    # Rkhunter
    if command -v rkhunter &>/dev/null; then
        info "Running rkhunter..."
        rkhunter --check --skip-keypress --report-warnings-only > "$scan_dir/rkhunter.log" 2>&1
        success "Rkhunter scan complete: $scan_dir/rkhunter.log"
    fi
    
    # Chkrootkit
    if command -v chkrootkit &>/dev/null; then
        info "Running chkrootkit..."
        chkrootkit > "$scan_dir/chkrootkit.log" 2>&1
        success "Chkrootkit scan complete: $scan_dir/chkrootkit.log"
    fi
    
    # Lynis
    if command -v lynis &>/dev/null; then
        info "Running lynis..."
        lynis audit system --quick --no-colors > "$scan_dir/lynis.log" 2>&1
        success "Lynis scan complete: $scan_dir/lynis.log"
    fi
    
    # Summary
    echo ""
    info "Scan results in: $scan_dir/"
    ls -la "$scan_dir/"
}

#=============================================================================
# QUICK MALWARE SCAN
#=============================================================================
quick_malware_scan() {
    header "Quick Malware Scan"
    
    if ! command -v clamscan &>/dev/null; then
        error "ClamAV not installed"
        return 1
    fi
    
    local targets="/tmp /var/tmp /dev/shm /home /var/www /srv"
    
    info "Scanning: $targets"
    clamscan -r --infected --exclude-dir="^/sys" $targets 2>/dev/null
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    echo ""
    echo "Security Tools Options:"
    echo "1) Install essential tools"
    echo "2) Install & configure auditd"
    echo "3) Install rkhunter"
    echo "4) Install chkrootkit"
    echo "5) Install lynis"
    echo "6) Install ClamAV"
    echo "7) Install AIDE"
    echo "8) Run security scans"
    echo "9) Quick malware scan"
    echo "10) Install ALL tools"
    echo ""
    read -p "Select option [1-10]: " choice
    
    case $choice in
        1) install_essential ;;
        2) install_auditd ;;
        3) install_rkhunter ;;
        4) install_chkrootkit ;;
        5) install_lynis ;;
        6) install_clamav ;;
        7) install_aide ;;
        8) run_security_scan ;;
        9) quick_malware_scan ;;
        10)
            install_essential
            install_auditd
            install_rkhunter
            install_chkrootkit
            install_lynis
            install_clamav
            ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
