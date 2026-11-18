#!/bin/bash
# CCDC26 Monarch - Kill Attacker Sessions
# Kill by username, TTY, or source IP
# SELF-CONTAINED -- no external dependencies

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then error "Must be run as root"; exit 1; fi

show_sessions() {
    echo ""
    info "Logged in users:"
    who -a 2>/dev/null
    echo ""
    info "SSH connections:"
    ss -tnp 2>/dev/null | grep ":22 " | grep ESTAB
    echo ""
}

echo -e "\n${BOLD}Kill Attacker Sessions${NC}\n"
show_sessions

echo "Options:"
echo "  1) Kill by username"
echo "  2) Kill by TTY"
echo "  3) Kill by source IP"
echo "  4) Kill suspicious processes (temp dirs, deleted bins)"
echo "  5) Force logout ALL other users"
echo ""
read -rp "Select [1-5]: " choice

case "$choice" in
    1)
        read -rp "Username to kill: " target_user
        [ -z "$target_user" ] && { error "No username"; exit 1; }
        [ "$target_user" = "$(whoami)" ] && { error "Cannot kill own session"; exit 1; }
        info "Killing all processes for $target_user..."
        pkill -9 -u "$target_user" 2>/dev/null
        ok "Killed sessions for $target_user"
        ;;
    2)
        read -rp "TTY to kill (e.g. pts/0): " target_tty
        [ -z "$target_tty" ] && { error "No TTY"; exit 1; }
        info "Killing all processes on $target_tty..."
        pkill -9 -t "$target_tty" 2>/dev/null
        ok "Killed processes on $target_tty"
        ;;
    3)
        read -rp "Source IP to kill: " target_ip
        [ -z "$target_ip" ] && { error "No IP"; exit 1; }
        pids=$(ss -tnp 2>/dev/null | grep "$target_ip" | grep -oP 'pid=\K[0-9]+' | sort -u)
        if [ -n "$pids" ]; then
            for pid in $pids; do
                kill -9 "$pid" 2>/dev/null
                info "Killed PID $pid"
            done
            ok "Killed connections from $target_ip"
        else
            warn "No connections found from $target_ip"
        fi
        read -rp "Block this IP in iptables? (y/n): " block
        if [[ "$block" =~ ^[Yy]$ ]]; then
            iptables -I INPUT -s "$target_ip" -j DROP
            iptables -I OUTPUT -d "$target_ip" -j DROP
            ok "Blocked $target_ip"
        fi
        ;;
    4)
        info "Killing processes from /tmp, /dev/shm, /var/tmp..."
        for pid in $(ps aux | awk '$11 ~ /^(\/tmp|\/dev\/shm|\/var\/tmp)/ {print $2}'); do
            kill -9 "$pid" 2>/dev/null && info "Killed PID $pid"
        done
        info "Killing processes with deleted binaries..."
        for pid in $(ls -la /proc/*/exe 2>/dev/null | grep deleted | grep -oP '/proc/\K[0-9]+'); do
            kill -9 "$pid" 2>/dev/null && info "Killed PID $pid (deleted binary)"
        done
        ok "Suspicious processes killed"
        ;;
    5)
        my_tty=$(tty 2>/dev/null | sed 's|/dev/||')
        who | while read -r user tty rest; do
            if [ "$tty" != "$my_tty" ]; then
                pkill -9 -t "$tty" 2>/dev/null
                info "Killed $user on $tty"
            fi
        done
        ok "Forced logout of all other users"
        ;;
    *)
        error "Invalid option"
        ;;
esac
