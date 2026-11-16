#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Network Isolation
# Isolate system during incident response

source "$(dirname "$0")/../utils/common.sh"
require_root

header "Network Isolation"

BACKUP_DIR="/var/lib/ccdc-toolkit/network-backup"
mkdir -p "$BACKUP_DIR"

#=============================================================================
# FULL ISOLATION (Emergency)
#=============================================================================
full_isolation() {
    header "FULL NETWORK ISOLATION"
    
    warn "This will DROP all network traffic except localhost!"
    warn "You may lose remote access!"
    
    read -p "Continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    # Backup current rules
    iptables-save > "$BACKUP_DIR/iptables-$(timestamp).rules"
    
    # Flush everything
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    
    # Drop all by default
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT DROP
    
    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    
    success "System is now FULLY ISOLATED"
    warn "To restore: iptables-restore < $BACKUP_DIR/iptables-*.rules"
    log_action "FULL NETWORK ISOLATION activated"
}

#=============================================================================
# ISOLATE EXCEPT SSH
#=============================================================================
isolate_except_ssh() {
    header "Isolation with SSH Access"
    
    read -p "Enter allowed SSH source IP (or CIDR): " allowed_ip
    
    if [ -z "$allowed_ip" ]; then
        error "Must specify allowed IP"
        return
    fi
    
    # Backup current rules
    iptables-save > "$BACKUP_DIR/iptables-$(timestamp).rules"
    
    # Flush everything
    iptables -F
    iptables -X
    
    # Drop all by default
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT DROP
    
    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    
    # Allow established connections
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    
    # Allow SSH from specific IP
    iptables -A INPUT -p tcp -s "$allowed_ip" --dport 22 -j ACCEPT
    iptables -A OUTPUT -p tcp --sport 22 -d "$allowed_ip" -j ACCEPT
    
    success "System isolated - SSH allowed only from $allowed_ip"
    log_action "Network isolation with SSH from $allowed_ip"
}

#=============================================================================
# BLOCK SPECIFIC IP
#=============================================================================
block_ip() {
    header "Block IP Address"
    
    read -p "Enter IP to block: " ip
    
    if [ -z "$ip" ]; then
        error "No IP provided"
        return
    fi
    
    iptables -I INPUT -s "$ip" -j DROP
    iptables -I OUTPUT -d "$ip" -j DROP
    iptables -I FORWARD -s "$ip" -j DROP
    iptables -I FORWARD -d "$ip" -j DROP
    
    success "Blocked all traffic to/from $ip"
    log_action "Blocked IP: $ip"
}

#=============================================================================
# BLOCK PORT
#=============================================================================
block_port() {
    header "Block Port"
    
    read -p "Enter port to block: " port
    read -p "Protocol (tcp/udp/both): " proto
    
    proto=${proto:-both}
    
    if [ -z "$port" ]; then
        error "No port provided"
        return
    fi
    
    if [ "$proto" == "both" ] || [ "$proto" == "tcp" ]; then
        iptables -I INPUT -p tcp --dport "$port" -j DROP
        iptables -I OUTPUT -p tcp --dport "$port" -j DROP
    fi
    
    if [ "$proto" == "both" ] || [ "$proto" == "udp" ]; then
        iptables -I INPUT -p udp --dport "$port" -j DROP
        iptables -I OUTPUT -p udp --dport "$port" -j DROP
    fi
    
    success "Blocked port $port ($proto)"
    log_action "Blocked port: $port ($proto)"
}

#=============================================================================
# BLOCK OUTBOUND
#=============================================================================
block_outbound() {
    header "Block Outbound Connections"
    
    warn "This blocks all outbound except established!"
    
    read -p "Continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    # Backup current rules
    iptables-save > "$BACKUP_DIR/iptables-$(timestamp).rules"
    
    # Drop outbound by default
    iptables -P OUTPUT DROP
    
    # Allow loopback
    iptables -A OUTPUT -o lo -j ACCEPT
    
    # Allow established
    iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    
    success "Outbound connections blocked"
    log_action "Blocked outbound connections"
}

#=============================================================================
# SHOW CURRENT RULES
#=============================================================================
show_rules() {
    header "Current Firewall Rules"
    
    iptables -L -n -v --line-numbers
}

#=============================================================================
# RESTORE RULES
#=============================================================================
restore_rules() {
    header "Restore Firewall Rules"
    
    info "Available backups:"
    ls -la "$BACKUP_DIR"/*.rules 2>/dev/null
    
    echo ""
    read -p "Enter backup filename to restore: " backup
    
    if [ -f "$backup" ]; then
        iptables-restore < "$backup"
        success "Restored rules from $backup"
        log_action "Restored firewall rules from $backup"
    elif [ -f "$BACKUP_DIR/$backup" ]; then
        iptables-restore < "$BACKUP_DIR/$backup"
        success "Restored rules from $BACKUP_DIR/$backup"
    else
        error "Backup file not found"
    fi
}

#=============================================================================
# REMOVE ALL BLOCKS (Reset)
#=============================================================================
reset_firewall() {
    header "Reset Firewall"
    
    warn "This will FLUSH all iptables rules!"
    
    read -p "Continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    # Backup first
    iptables-save > "$BACKUP_DIR/iptables-$(timestamp).rules"
    
    # Flush all
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    
    # Accept all by default
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    
    success "Firewall rules cleared"
    warn "System is now UNPROTECTED"
    log_action "Reset firewall rules"
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    echo ""
    echo "Network Isolation Options:"
    echo "1) FULL isolation (drop all)"
    echo "2) Isolate except SSH (from specific IP)"
    echo "3) Block specific IP"
    echo "4) Block specific port"
    echo "5) Block all outbound"
    echo "6) Show current rules"
    echo "7) Restore from backup"
    echo "8) Reset firewall (DANGEROUS)"
    echo ""
    read -p "Select option [1-8]: " choice
    
    case $choice in
        1) full_isolation ;;
        2) isolate_except_ssh ;;
        3) block_ip ;;
        4) block_port ;;
        5) block_outbound ;;
        6) show_rules ;;
        7) restore_rules ;;
        8) reset_firewall ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
