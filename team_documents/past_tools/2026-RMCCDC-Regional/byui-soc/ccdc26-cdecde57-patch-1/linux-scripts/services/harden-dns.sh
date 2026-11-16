#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - DNS Server Hardening
# Secure BIND/named DNS server

source "$(dirname "$0")/../utils/common.sh"
require_root

header "DNS Server Hardening"

#=============================================================================
# DETECT DNS SERVER
#=============================================================================
detect_dns_server() {
    DNS_SERVER="none"
    NAMED_CONF=""
    
    if systemctl is-active named &>/dev/null || systemctl is-active bind9 &>/dev/null; then
        DNS_SERVER="bind"
        for conf in /etc/named.conf /etc/bind/named.conf; do
            [ -f "$conf" ] && NAMED_CONF="$conf" && break
        done
    fi
    
    [ "$DNS_SERVER" == "none" ] && warn "No DNS server detected" && return 1
    info "Detected: $DNS_SERVER ($NAMED_CONF)"
    return 0
}

#=============================================================================
# HARDEN BIND
#=============================================================================
harden_bind() {
    header "Hardening BIND/named"
    
    [ -z "$NAMED_CONF" ] && error "Config not found" && return 1
    backup_file "$NAMED_CONF"
    
    local options_file="/etc/bind/named.conf.options"
    [ ! -f "$options_file" ] && options_file="$NAMED_CONF"
    backup_file "$options_file"
    
    # Create secure options
    if [ -f /etc/bind/named.conf.options ]; then
        cat > /etc/bind/named.conf.options << 'EOF'
options {
    directory "/var/cache/bind";
    listen-on port 53 { 127.0.0.1; any; };
    allow-transfer { none; };
    recursion yes;
    allow-recursion { 127.0.0.1; 10.0.0.0/8; 172.16.0.0/12; 192.168.0.0/16; };
    allow-query { any; };
    version "not available";
    hostname "not available";
    dnssec-validation auto;
    minimal-responses yes;
    notify no;
    querylog yes;
};
EOF
    fi
    
    mkdir -p /var/log/named
    chown bind:bind /var/log/named 2>/dev/null || chown named:named /var/log/named
    
    if named-checkconf 2>/dev/null; then
        success "Configuration valid"
        systemctl restart bind9 2>/dev/null || systemctl restart named
        success "BIND restarted"
    else
        error "Configuration error!"
    fi
    
    log_action "Hardened BIND"
}

#=============================================================================
# CHECK DNS SECURITY
#=============================================================================
check_dns_security() {
    header "Checking DNS Security"
    
    info "=== Recursion Settings ==="
    grep -r "recursion\|allow-recursion" /etc/bind /etc/named* 2>/dev/null | grep -v "^#"
    
    info "=== Zone Transfer Settings ==="
    grep -r "allow-transfer" /etc/bind /etc/named* 2>/dev/null | grep -v "^#"
    
    info "=== Version Check ==="
    dig @127.0.0.1 version.bind txt chaos 2>/dev/null | grep -i version
    
    info "=== DNS Ports ==="
    ss -ulnp | grep :53
    ss -tlnp | grep :53
}

#=============================================================================
# AUDIT ZONES
#=============================================================================
audit_zones() {
    header "Auditing DNS Zones"
    
    for dir in /var/named /var/cache/bind /etc/bind/zones; do
        [ -d "$dir" ] || continue
        info "=== Zones in $dir ==="
        find "$dir" -type f \( -name "*.zone" -o -name "db.*" \) 2>/dev/null
    done
    
    info "=== Configured Zones ==="
    grep -r "zone\s*\"" /etc/bind /etc/named* 2>/dev/null | grep -v "^#" | head -20
}

#=============================================================================
# CHECK DNS HIJACKING
#=============================================================================
check_dns_hijacking() {
    header "Checking for DNS Hijacking"
    
    info "=== /etc/resolv.conf ==="
    cat /etc/resolv.conf
    
    [ -L /etc/resolv.conf ] && warn "resolv.conf is symlink: $(readlink /etc/resolv.conf)"
    
    info "=== Testing Resolution ==="
    for domain in google.com; do
        local local_ip=$(dig @127.0.0.1 +short "$domain" 2>/dev/null | head -1)
        local google_ip=$(dig @8.8.8.8 +short "$domain" 2>/dev/null | head -1)
        echo "  Local: $local_ip | Google: $google_ip"
        [ "$local_ip" != "$google_ip" ] && warn "Mismatch detected!"
    done
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    detect_dns_server
    
    echo ""
    echo "DNS Hardening Options:"
    echo "1) Harden BIND"
    echo "2) Check DNS security"
    echo "3) Audit zones"
    echo "4) Check for DNS hijacking"
    echo "5) Run ALL"
    echo ""
    read -p "Select option [1-5]: " choice
    
    case $choice in
        1) harden_bind ;;
        2) check_dns_security ;;
        3) audit_zones ;;
        4) check_dns_hijacking ;;
        5) harden_bind; check_dns_security; audit_zones; check_dns_hijacking ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
