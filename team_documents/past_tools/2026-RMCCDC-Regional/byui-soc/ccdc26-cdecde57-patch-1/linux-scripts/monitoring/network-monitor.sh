#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Network Monitor
# Monitor network connections and traffic

source "$(dirname "$0")/../utils/common.sh"
require_root

header "Network Monitor"

#=============================================================================
# SHOW LISTENING PORTS
#=============================================================================
show_listeners() {
    header "Listening Ports"
    
    info "TCP listeners:"
    if command -v ss &>/dev/null; then
        ss -tlnp
    else
        netstat -tlnp
    fi
    
    echo ""
    info "UDP listeners:"
    if command -v ss &>/dev/null; then
        ss -ulnp
    else
        netstat -ulnp
    fi
}

#=============================================================================
# SHOW ESTABLISHED CONNECTIONS
#=============================================================================
show_established() {
    header "Established Connections"
    
    if command -v ss &>/dev/null; then
        ss -tnp state established
    else
        netstat -tnp | grep ESTABLISHED
    fi
}

#=============================================================================
# FIND SUSPICIOUS CONNECTIONS
#=============================================================================
find_suspicious_connections() {
    header "Scanning for Suspicious Connections"
    
    # Connections to unusual ports
    info "Connections to unusual destination ports..."
    if command -v ss &>/dev/null; then
        ss -tnp | grep -vE ':22 |:80 |:443 |:53 |:25 ' | grep ESTAB | while read -r line; do
            warn "Unusual connection: $line"
        done
    fi
    
    # Connections to external IPs
    info "Connections to external IPs..."
    if command -v ss &>/dev/null; then
        ss -tnp 2>/dev/null | grep ESTAB | grep -vE '(127\.0\.0\.1|::1|10\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[0-1]\.|192\.168\.)' | while read -r line; do
            log_finding "External connection: $line"
        done
    fi
    
    # Reverse shells (common ports)
    info "Checking for potential reverse shells..."
    local reverse_ports=(4444 5555 6666 7777 8888 9999 1234 31337)
    for port in "${reverse_ports[@]}"; do
        if ss -tnp 2>/dev/null | grep -q ":$port "; then
            log_finding "Connection on suspicious port $port"
        fi
    done
    
    # Raw sockets
    info "Checking for raw sockets..."
    if command -v ss &>/dev/null; then
        ss -wlnp 2>/dev/null | grep -v "^Netid" | while read -r line; do
            [ -n "$line" ] && log_finding "Raw socket: $line"
        done
    fi
}

#=============================================================================
# MONITOR CONNECTIONS IN REAL-TIME
#=============================================================================
monitor_connections() {
    header "Monitoring Connections"
    info "Press Ctrl+C to stop."
    
    local prev_conns=$(ss -tnp 2>/dev/null | sort)
    
    while true; do
        sleep 3
        local curr_conns=$(ss -tnp 2>/dev/null | sort)
        
        # New connections
        local new_conns=$(comm -13 <(echo "$prev_conns") <(echo "$curr_conns"))
        echo "$new_conns" | while read -r line; do
            [ -n "$line" ] && [ "$line" != "State" ] && echo -e "${GREEN}[NEW]${NC} $line"
        done
        
        # Closed connections
        local closed_conns=$(comm -23 <(echo "$prev_conns") <(echo "$curr_conns"))
        echo "$closed_conns" | while read -r line; do
            [ -n "$line" ] && [ "$line" != "State" ] && echo -e "${RED}[CLOSED]${NC} $line"
        done
        
        prev_conns="$curr_conns"
    done
}

#=============================================================================
# SHOW NETWORK INTERFACES
#=============================================================================
show_interfaces() {
    header "Network Interfaces"
    
    ip addr show
    
    echo ""
    info "Routing table:"
    ip route show
    
    echo ""
    info "ARP table:"
    ip neigh show
}

#=============================================================================
# CHECK FOR PROMISCUOUS MODE
#=============================================================================
check_promiscuous() {
    header "Checking Promiscuous Mode"
    
    ip link show | grep -i promisc
    if [ $? -eq 0 ]; then
        log_finding "Interface in promiscuous mode detected!"
    else
        success "No interfaces in promiscuous mode"
    fi
}

#=============================================================================
# CAPTURE TRAFFIC (brief)
#=============================================================================
capture_traffic() {
    header "Capturing Network Traffic"
    
    if ! command -v tcpdump &>/dev/null; then
        info "Installing tcpdump..."
        pkg_install tcpdump
    fi
    
    if ! command -v tcpdump &>/dev/null; then
        error "Cannot install tcpdump"
        return
    fi
    
    read -p "Interface to capture (default: any): " iface
    iface=${iface:-any}
    
    read -p "Duration in seconds (default: 30): " duration
    duration=${duration:-30}
    
    local outfile="/tmp/capture-$(timestamp).pcap"
    
    info "Capturing on $iface for $duration seconds..."
    timeout "$duration" tcpdump -i "$iface" -w "$outfile" -c 10000 2>/dev/null &
    
    sleep "$duration"
    
    success "Capture saved to: $outfile"
    info "Packet count: $(tcpdump -r "$outfile" 2>/dev/null | wc -l)"
}

#=============================================================================
# BLOCK IP
#=============================================================================
block_ip() {
    header "Block IP Address"
    
    read -p "Enter IP to block: " ip
    [ -z "$ip" ] && return
    
    detect_firewall
    
    case "$FIREWALL" in
        ufw)
            ufw deny from "$ip"
            ;;
        firewalld)
            firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='$ip' reject"
            firewall-cmd --reload
            ;;
        iptables|*)
            iptables -I INPUT -s "$ip" -j DROP
            iptables -I OUTPUT -d "$ip" -j DROP
            ;;
    esac
    
    success "Blocked IP: $ip"
    log_action "Blocked IP: $ip"
}

#=============================================================================
# DNS LOOKUPS
#=============================================================================
check_dns() {
    header "DNS Configuration"
    
    info "Resolv.conf:"
    cat /etc/resolv.conf
    
    echo ""
    info "Hosts file:"
    grep -v "^#" /etc/hosts | grep -v "^$"
    
    # Check for DNS hijacking
    info "Testing DNS resolution..."
    for domain in google.com microsoft.com anthropic.com; do
        local resolved=$(dig +short "$domain" 2>/dev/null | head -1)
        echo "  $domain -> $resolved"
    done
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    echo ""
    echo "Network Monitor Options:"
    echo "1) Show listening ports"
    echo "2) Show established connections"
    echo "3) Find suspicious connections"
    echo "4) Monitor connections (live)"
    echo "5) Show network interfaces"
    echo "6) Check promiscuous mode"
    echo "7) Capture traffic"
    echo "8) Block IP address"
    echo "9) Check DNS configuration"
    echo ""
    read -p "Select option [1-9]: " choice
    
    case $choice in
        1) show_listeners ;;
        2) show_established ;;
        3) find_suspicious_connections ;;
        4) monitor_connections ;;
        5) show_interfaces ;;
        6) check_promiscuous ;;
        7) capture_traffic ;;
        8) block_ip ;;
        9) check_dns ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
