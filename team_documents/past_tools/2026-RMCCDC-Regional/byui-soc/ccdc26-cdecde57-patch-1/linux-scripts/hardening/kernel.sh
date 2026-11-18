#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Kernel Parameter Hardening
# Secure sysctl settings and kernel parameters

source "$(dirname "$0")/../utils/common.sh"
require_root

header "Kernel Parameter Hardening"

#=============================================================================
# SYSCTL HARDENING
#=============================================================================
harden_sysctl() {
    header "Hardening Sysctl Parameters"
    
    backup_file /etc/sysctl.conf
    
    cat > /etc/sysctl.d/99-ccdc-hardening.conf << 'EOF'
# CCDC26 Kernel Hardening

# Network Security
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.log_martians = 1

# Memory Protection
fs.suid_dumpable = 0
kernel.randomize_va_space = 2
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.perf_event_paranoid = 3

# Filesystem Security
fs.protected_symlinks = 1
fs.protected_hardlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
EOF

    sysctl -p /etc/sysctl.d/99-ccdc-hardening.conf 2>/dev/null
    success "Sysctl parameters hardened"
    log_action "Applied sysctl hardening"
}

#=============================================================================
# AUDIT KERNEL PARAMETERS
#=============================================================================
audit_kernel_params() {
    header "Auditing Kernel Parameters"
    
    declare -A expected_values=(
        ["net.ipv4.ip_forward"]="0"
        ["net.ipv4.conf.all.accept_redirects"]="0"
        ["net.ipv4.tcp_syncookies"]="1"
        ["kernel.randomize_va_space"]="2"
        ["fs.suid_dumpable"]="0"
    )
    
    for param in "${!expected_values[@]}"; do
        local current=$(sysctl -n "$param" 2>/dev/null)
        local expected="${expected_values[$param]}"
        
        if [ "$current" == "$expected" ]; then
            success "$param = $current"
        else
            log_finding "$param = $current (expected: $expected)"
        fi
    done
}

#=============================================================================
# DISABLE DANGEROUS MODULES
#=============================================================================
disable_dangerous_modules() {
    header "Disabling Dangerous Kernel Modules"
    
    local modules=("dccp" "sctp" "rds" "tipc" "cramfs" "freevxfs" "hfs" "hfsplus" "udf")
    
    cat > /etc/modprobe.d/ccdc-blacklist.conf << 'EOF'
# CCDC26 - Blacklisted kernel modules
EOF

    for mod in "${modules[@]}"; do
        echo "install $mod /bin/true" >> /etc/modprobe.d/ccdc-blacklist.conf
        echo "blacklist $mod" >> /etc/modprobe.d/ccdc-blacklist.conf
        rmmod "$mod" 2>/dev/null
    done
    
    success "Created kernel module blacklist"
    log_action "Disabled dangerous kernel modules"
}

#=============================================================================
# AUDIT KERNEL MODULES
#=============================================================================
audit_kernel_modules() {
    header "Auditing Loaded Kernel Modules"
    
    info "Currently loaded modules:"
    lsmod | head -20
    
    info "Recently modified modules (last 7 days):"
    find /lib/modules/$(uname -r) -name "*.ko*" -mtime -7 2>/dev/null | head -10
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    echo ""
    echo "Kernel Hardening Options:"
    echo "1) Audit kernel parameters"
    echo "2) Harden sysctl parameters"
    echo "3) Audit kernel modules"
    echo "4) Disable dangerous modules"
    echo "5) Run ALL"
    echo ""
    read -p "Select option [1-5]: " choice
    
    case $choice in
        1) audit_kernel_params ;;
        2) harden_sysctl ;;
        3) audit_kernel_modules ;;
        4) disable_dangerous_modules ;;
        5)
            audit_kernel_params
            harden_sysctl
            audit_kernel_modules
            disable_dangerous_modules
            ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
