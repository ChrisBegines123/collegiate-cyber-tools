#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Firewall Configuration
# Cross-distribution firewall management

source "$(dirname "$0")/../utils/common.sh"
require_root

header "Firewall Configuration"

#=============================================================================
# CONFIGURATION - EDIT THESE FOR YOUR SERVICES
#=============================================================================
# CCDC SERVICE DETECTION - Auto-detect running services and allow their ports
# This prevents accidentally blocking scored services!

detect_running_services() {
    local detected_tcp=""
    local detected_udp=""
    
    # Always allow SSH
    detected_tcp="22"
    
    # Check for web servers (HTTP/HTTPS - SCORED)
    if systemctl is-active apache2 &>/dev/null || systemctl is-active httpd &>/dev/null || \
       systemctl is-active nginx &>/dev/null || pgrep -x "apache2\|httpd\|nginx" &>/dev/null; then
        detected_tcp="$detected_tcp 80 443"
        info "Detected: Web server (HTTP/HTTPS)"
    fi
    
    # Check for mail servers (SMTP/POP3 - SCORED)
    if systemctl is-active postfix &>/dev/null || systemctl is-active sendmail &>/dev/null || \
       pgrep -x "master\|postfix\|sendmail" &>/dev/null; then
        detected_tcp="$detected_tcp 25 587"
        info "Detected: Mail server (SMTP)"
    fi
    if systemctl is-active dovecot &>/dev/null || pgrep -x "dovecot" &>/dev/null; then
        detected_tcp="$detected_tcp 110 143 993 995"
        info "Detected: Mail server (POP3/IMAP)"
    fi
    
    # Check for DNS (SCORED on Windows but might exist on Linux)
    if systemctl is-active named &>/dev/null || systemctl is-active bind9 &>/dev/null || \
       pgrep -x "named" &>/dev/null; then
        detected_tcp="$detected_tcp 53"
        detected_udp="$detected_udp 53"
        info "Detected: DNS server"
    fi
    
    # Check for FTP
    if systemctl is-active vsftpd &>/dev/null || systemctl is-active proftpd &>/dev/null || \
       pgrep -x "vsftpd\|proftpd" &>/dev/null; then
        detected_tcp="$detected_tcp 21 20"
        info "Detected: FTP server"
    fi
    
    # Check for database servers
    if systemctl is-active mysql &>/dev/null || systemctl is-active mariadb &>/dev/null; then
        detected_tcp="$detected_tcp 3306"
        info "Detected: MySQL/MariaDB"
    fi
    if systemctl is-active postgresql &>/dev/null; then
        detected_tcp="$detected_tcp 5432"
        info "Detected: PostgreSQL"
    fi
    
    # Check for Splunk (competition has Splunk server)
    if systemctl is-active splunk &>/dev/null || pgrep -f "splunkd" &>/dev/null; then
        detected_tcp="$detected_tcp 8000 8089 9997"
        info "Detected: Splunk"
    fi
    
    # Check for Splunk
    if systemctl is-active splunk &>/dev/null || [ -f /opt/splunk/bin/splunk ]; then
        detected_tcp="$detected_tcp 9997 8000 8089"
        info "Detected: Splunk Server"
    fi
    
    # Remove duplicates and format
    DETECTED_TCP_PORTS=$(echo "$detected_tcp" | tr ' ' '\n' | sort -un | tr '\n' ' ')
    DETECTED_UDP_PORTS=$(echo "$detected_udp" | tr ' ' '\n' | sort -un | tr '\n' ' ')
}

# Run detection
detect_running_services

# Allowed inbound TCP ports (space-separated)
# Auto-detected from running services - add more as needed
ALLOWED_TCP_PORTS="${DETECTED_TCP_PORTS:-22 80 443}"

# Allowed inbound UDP ports (space-separated)
ALLOWED_UDP_PORTS="${DETECTED_UDP_PORTS:-}"

# Allowed source networks (CIDR notation, space-separated)
# Leave empty to allow from anywhere
ALLOWED_NETWORKS=""     # e.g., "10.0.0.0/8 192.168.0.0/16"

# Management/scoring network (always allowed)
# CCDC scoring comes from the competition infrastructure
SCORING_NETWORK=""      # e.g., "172.25.0.0/16" for competition scoring

#=============================================================================
# UFW (Ubuntu/Debian)
#=============================================================================
configure_ufw() {
    header "Configuring UFW Firewall"
    
    if ! command -v ufw &>/dev/null; then
        info "Installing UFW..."
        apt-get update && apt-get install -y ufw
    fi
    
    # Reset to defaults
    info "Resetting UFW to defaults..."
    ufw --force reset
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow scoring network if specified
    if [ -n "$SCORING_NETWORK" ]; then
        ufw allow from "$SCORING_NETWORK"
        info "Allowed all traffic from scoring network: $SCORING_NETWORK"
    fi
    
    # Allow TCP ports
    for port in $ALLOWED_TCP_PORTS; do
        if [ -n "$ALLOWED_NETWORKS" ]; then
            for net in $ALLOWED_NETWORKS; do
                ufw allow from "$net" to any port "$port" proto tcp
            done
        else
            ufw allow "$port/tcp"
        fi
        info "Allowed TCP port: $port"
    done
    
    # Allow UDP ports
    for port in $ALLOWED_UDP_PORTS; do
        if [ -n "$ALLOWED_NETWORKS" ]; then
            for net in $ALLOWED_NETWORKS; do
                ufw allow from "$net" to any port "$port" proto udp
            done
        else
            ufw allow "$port/udp"
        fi
        info "Allowed UDP port: $port"
    done
    
    # Enable logging
    ufw logging on
    ufw logging high
    
    # Enable firewall
    ufw --force enable
    
    success "UFW configured and enabled"
    ufw status verbose
    log_action "Configured UFW firewall"
}

#=============================================================================
# FIREWALLD (RHEL/CentOS/Fedora)
#=============================================================================
configure_firewalld() {
    header "Configuring Firewalld"
    
    if ! command -v firewall-cmd &>/dev/null; then
        info "Installing firewalld..."
        $PKG_MGR install -y firewalld
    fi
    
    # Start and enable
    systemctl start firewalld
    systemctl enable firewalld
    
    # Set default zone to drop
    firewall-cmd --set-default-zone=drop
    
    # Remove all services from default zone
    for service in $(firewall-cmd --list-services); do
        firewall-cmd --permanent --remove-service="$service"
    done
    
    # Allow scoring network if specified
    if [ -n "$SCORING_NETWORK" ]; then
        firewall-cmd --permanent --add-source="$SCORING_NETWORK"
        firewall-cmd --permanent --zone=trusted --add-source="$SCORING_NETWORK"
        info "Allowed scoring network: $SCORING_NETWORK"
    fi
    
    # Allow TCP ports
    for port in $ALLOWED_TCP_PORTS; do
        firewall-cmd --permanent --add-port="${port}/tcp"
        info "Allowed TCP port: $port"
    done
    
    # Allow UDP ports
    for port in $ALLOWED_UDP_PORTS; do
        firewall-cmd --permanent --add-port="${port}/udp"
        info "Allowed UDP port: $port"
    done
    
    # Enable logging
    firewall-cmd --permanent --set-log-denied=all
    
    # Reload
    firewall-cmd --reload
    
    success "Firewalld configured"
    firewall-cmd --list-all
    log_action "Configured firewalld"
}

#=============================================================================
# IPTABLES (Universal fallback)
#=============================================================================
configure_iptables() {
    header "Configuring iptables"
    
    # Backup current rules
    iptables-save > "/root/iptables-backup-$(timestamp).rules"
    
    # Flush existing rules
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    
    # Default policies
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT
    
    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    
    # Allow established connections
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    
    # Allow scoring network if specified
    if [ -n "$SCORING_NETWORK" ]; then
        iptables -A INPUT -s "$SCORING_NETWORK" -j ACCEPT
        info "Allowed scoring network: $SCORING_NETWORK"
    fi
    
    # Allow TCP ports
    for port in $ALLOWED_TCP_PORTS; do
        if [ -n "$ALLOWED_NETWORKS" ]; then
            for net in $ALLOWED_NETWORKS; do
                iptables -A INPUT -p tcp -s "$net" --dport "$port" -j ACCEPT
            done
        else
            iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
        fi
        info "Allowed TCP port: $port"
    done
    
    # Allow UDP ports
    for port in $ALLOWED_UDP_PORTS; do
        if [ -n "$ALLOWED_NETWORKS" ]; then
            for net in $ALLOWED_NETWORKS; do
                iptables -A INPUT -p udp -s "$net" --dport "$port" -j ACCEPT
            done
        else
            iptables -A INPUT -p udp --dport "$port" -j ACCEPT
        fi
        info "Allowed UDP port: $port"
    done
    
    # Allow ICMP (ping) - optional, comment out to disable
    iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
    
    # Log dropped packets
    iptables -A INPUT -j LOG --log-prefix "IPTABLES_DROP: " --log-level 4
    
    # Drop everything else (already default, but explicit)
    iptables -A INPUT -j DROP
    
    # Save rules
    case "$DISTRO_FAMILY" in
        debian)
            if command -v netfilter-persistent &>/dev/null; then
                netfilter-persistent save
            else
                iptables-save > /etc/iptables.rules
                echo '#!/bin/sh' > /etc/network/if-pre-up.d/iptables
                echo 'iptables-restore < /etc/iptables.rules' >> /etc/network/if-pre-up.d/iptables
                chmod +x /etc/network/if-pre-up.d/iptables
            fi
            ;;
        rhel)
            service iptables save 2>/dev/null || iptables-save > /etc/sysconfig/iptables
            ;;
        alpine)
            /etc/init.d/iptables save 2>/dev/null || iptables-save > /etc/iptables/rules-save
            ;;
    esac
    
    success "iptables configured"
    iptables -L -n -v
    log_action "Configured iptables"
}

#=============================================================================
# NFTABLES (Modern replacement)
#=============================================================================
configure_nftables() {
    header "Configuring nftables"
    
    if ! command -v nft &>/dev/null; then
        error "nftables not installed"
        return 1
    fi
    
    # Backup existing rules
    nft list ruleset > "/root/nftables-backup-$(timestamp).rules"
    
    # Flush existing rules
    nft flush ruleset
    
    # Create base ruleset
    cat > /etc/nftables.conf << 'EOF'
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        
        # Allow loopback
        iif lo accept
        
        # Allow established/related
        ct state established,related accept
        
        # Allow ICMP
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept
        
EOF

    # Add TCP port rules
    for port in $ALLOWED_TCP_PORTS; do
        echo "        tcp dport $port accept" >> /etc/nftables.conf
    done
    
    # Add UDP port rules
    for port in $ALLOWED_UDP_PORTS; do
        echo "        udp dport $port accept" >> /etc/nftables.conf
    done
    
    # Add scoring network if specified
    if [ -n "$SCORING_NETWORK" ]; then
        echo "        ip saddr $SCORING_NETWORK accept" >> /etc/nftables.conf
    fi
    
    # Close the config
    cat >> /etc/nftables.conf << 'EOF'
        
        # Log dropped
        log prefix "NFTABLES_DROP: " drop
    }
    
    chain forward {
        type filter hook forward priority 0; policy drop;
    }
    
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

    # Apply rules
    nft -f /etc/nftables.conf
    
    success "nftables configured"
    nft list ruleset
    log_action "Configured nftables"
}

#=============================================================================
# AUTO-DETECT AND CONFIGURE
#=============================================================================
auto_configure() {
    header "Auto-detecting and Configuring Firewall"
    
    detect_firewall
    
    case "$FIREWALL" in
        ufw)
            configure_ufw
            ;;
        firewalld)
            configure_firewalld
            ;;
        nftables)
            configure_nftables
            ;;
        iptables|*)
            configure_iptables
            ;;
    esac
}

#=============================================================================
# SHOW CURRENT RULES
#=============================================================================
show_current_rules() {
    header "Current Firewall Rules"
    
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
        info "UFW Status:"
        ufw status verbose
    fi
    
    if command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
        info "Firewalld Status:"
        firewall-cmd --list-all
    fi
    
    if command -v nft &>/dev/null && nft list ruleset 2>/dev/null | grep -q "table"; then
        info "nftables Rules:"
        nft list ruleset
    fi
    
    if command -v iptables &>/dev/null; then
        info "iptables Rules:"
        iptables -L -n -v --line-numbers
    fi
}

#=============================================================================
# QUICK LOCKDOWN (Emergency)
#=============================================================================
emergency_lockdown() {
    header "EMERGENCY FIREWALL LOCKDOWN"
    warn "This will block ALL incoming except SSH!"
    
    read -p "Continue with emergency lockdown? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    ALLOWED_TCP_PORTS="22"
    ALLOWED_UDP_PORTS=""
    
    auto_configure
    
    success "Emergency lockdown complete - only SSH (22) allowed"
    log_action "Emergency firewall lockdown executed"
}

#=============================================================================
# DISABLE FIREWALL (Use with caution)
#=============================================================================
disable_firewall() {
    header "Disabling Firewall"
    warn "This will disable the firewall completely!"
    
    read -p "Are you sure? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    # UFW
    ufw disable 2>/dev/null
    
    # Firewalld
    systemctl stop firewalld 2>/dev/null
    systemctl disable firewalld 2>/dev/null
    
    # iptables
    iptables -F
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    
    warn "Firewall disabled"
    log_action "Disabled firewall"
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    echo ""
    echo "Current allowed ports: TCP=$ALLOWED_TCP_PORTS UDP=$ALLOWED_UDP_PORTS"
    echo ""
    echo "Firewall Options:"
    echo "1) Show current rules"
    echo "2) Auto-detect and configure"
    echo "3) Configure UFW (Debian/Ubuntu)"
    echo "4) Configure Firewalld (RHEL/CentOS)"
    echo "5) Configure iptables (Universal)"
    echo "6) Configure nftables"
    echo "7) EMERGENCY lockdown (SSH only)"
    echo "8) Disable firewall (DANGEROUS)"
    echo ""
    read -p "Select option [1-8]: " choice
    
    case $choice in
        1) show_current_rules ;;
        2) auto_configure ;;
        3) configure_ufw ;;
        4) configure_firewalld ;;
        5) configure_iptables ;;
        6) configure_nftables ;;
        7) emergency_lockdown ;;
        8) disable_firewall ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
