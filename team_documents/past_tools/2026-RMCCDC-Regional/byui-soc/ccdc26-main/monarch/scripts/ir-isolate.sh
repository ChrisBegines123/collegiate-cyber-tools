#!/bin/bash
# CCDC26 Monarch - Network Isolation
# Full isolation (drop all except loopback) or SSH-only mode
# SELF-CONTAINED -- no external dependencies

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then error "Must be run as root"; exit 1; fi

BACKUP_DIR="/var/lib/ccdc-fw-backup"
mkdir -p "$BACKUP_DIR"
TS=$(date +%Y%m%d_%H%M%S)

echo -e "\n${BOLD}CCDC26 Network Isolation${NC}\n"

echo "Options:"
echo "  1) FULL isolation (drop ALL traffic, loopback only)"
echo "  2) SSH-only (allow SSH from specific IP, drop rest)"
echo "  3) Block specific IP"
echo "  4) Show current rules"
echo "  5) Restore from backup"
echo ""
read -rp "Select [1-5]: " choice

case "$choice" in
    1)
        warn "FULL ISOLATION -- you will lose remote access!"
        read -rp "Continue? (y/n): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 0

        iptables-save > "$BACKUP_DIR/iptables-${TS}.rules"
        iptables -F; iptables -X; iptables -t nat -F; iptables -t nat -X
        iptables -P INPUT DROP; iptables -P FORWARD DROP; iptables -P OUTPUT DROP
        iptables -A INPUT -i lo -j ACCEPT; iptables -A OUTPUT -o lo -j ACCEPT

        ok "System is FULLY ISOLATED"
        warn "Restore: iptables-restore < $BACKUP_DIR/iptables-${TS}.rules"
        ;;
    2)
        read -rp "Allowed SSH source IP/CIDR: " allowed_ip
        [ -z "$allowed_ip" ] && { error "Must specify IP"; exit 1; }

        iptables-save > "$BACKUP_DIR/iptables-${TS}.rules"
        iptables -F; iptables -X
        iptables -P INPUT DROP; iptables -P FORWARD DROP; iptables -P OUTPUT DROP
        iptables -A INPUT -i lo -j ACCEPT; iptables -A OUTPUT -o lo -j ACCEPT
        iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        iptables -A INPUT -p tcp -s "$allowed_ip" --dport 22 -j ACCEPT
        iptables -A OUTPUT -p tcp --sport 22 -d "$allowed_ip" -j ACCEPT

        ok "Isolated -- SSH only from $allowed_ip"
        warn "Restore: iptables-restore < $BACKUP_DIR/iptables-${TS}.rules"
        ;;
    3)
        read -rp "IP to block: " block_ip
        [ -z "$block_ip" ] && { error "No IP"; exit 1; }
        iptables -I INPUT -s "$block_ip" -j DROP
        iptables -I OUTPUT -d "$block_ip" -j DROP
        iptables -I FORWARD -s "$block_ip" -j DROP
        iptables -I FORWARD -d "$block_ip" -j DROP
        ok "Blocked all traffic to/from $block_ip"
        ;;
    4)
        iptables -L -n -v --line-numbers
        ;;
    5)
        info "Available backups:"
        ls -la "$BACKUP_DIR"/*.rules 2>/dev/null || { warn "No backups found"; exit 1; }
        read -rp "Backup file to restore: " restore_file
        if [ -f "$restore_file" ]; then
            iptables-restore < "$restore_file"
            ok "Restored from $restore_file"
        elif [ -f "$BACKUP_DIR/$restore_file" ]; then
            iptables-restore < "$BACKUP_DIR/$restore_file"
            ok "Restored from $BACKUP_DIR/$restore_file"
        else
            error "File not found"
        fi
        ;;
    *)
        error "Invalid option"
        ;;
esac
