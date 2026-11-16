#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Kill Attacker Sessions
# Terminate attacker connections and processes

source "$(dirname "$0")/../utils/common.sh"
require_root

header "Kill Attacker Sessions"

#=============================================================================
# SHOW ACTIVE SESSIONS
#=============================================================================
show_sessions() {
    header "Active Sessions"
    
    info "Logged in users:"
    who -a
    
    echo ""
    info "User TTY processes:"
    ps aux | grep -E 'pts/|tty/' | grep -v grep
    
    echo ""
    info "SSH connections:"
    ss -tnp | grep ":22 " | grep ESTAB
}

#=============================================================================
# KILL USER SESSION
#=============================================================================
kill_user_session() {
    header "Kill User Session"
    
    show_sessions
    
    echo ""
    read -p "Enter username to kill all sessions: " username
    
    if [ -z "$username" ]; then
        error "No username provided"
        return
    fi
    
    # Check if user exists
    if ! id "$username" &>/dev/null; then
        error "User $username does not exist"
        return
    fi
    
    # Don't kill yourself
    if [ "$username" == "$(whoami)" ]; then
        error "Cannot kill your own session!"
        return
    fi
    
    info "Processes owned by $username:"
    ps -u "$username" -o pid,tty,cmd
    
    read -p "Kill all processes for $username? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pkill -9 -u "$username"
        success "Killed all processes for $username"
        log_action "Killed all sessions for user: $username"
    fi
}

#=============================================================================
# KILL BY TTY
#=============================================================================
kill_by_tty() {
    header "Kill by TTY"
    
    info "Active TTYs:"
    who | awk '{print $2, $1, $5}'
    
    echo ""
    read -p "Enter TTY to kill (e.g., pts/0): " tty
    
    if [ -z "$tty" ]; then
        error "No TTY provided"
        return
    fi
    
    info "Processes on $tty:"
    ps aux | grep "$tty" | grep -v grep
    
    read -p "Kill all processes on $tty? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pkill -9 -t "$tty"
        success "Killed processes on $tty"
        log_action "Killed processes on TTY: $tty"
    fi
}

#=============================================================================
# KILL BY IP
#=============================================================================
kill_by_ip() {
    header "Kill by Source IP"
    
    info "SSH connections with source IPs:"
    ss -tnp | grep ":22 " | grep ESTAB
    
    echo ""
    info "Current logins with IPs:"
    who --ips 2>/dev/null || who
    
    echo ""
    read -p "Enter IP to kill connections from: " ip
    
    if [ -z "$ip" ]; then
        error "No IP provided"
        return
    fi
    
    # Find processes connected from this IP
    info "Finding connections from $ip..."
    
    # Get SSH connections from this IP
    local ssh_pids=$(ss -tnp | grep "$ip" | grep -oP 'pid=\K[0-9]+')
    
    if [ -n "$ssh_pids" ]; then
        for pid in $ssh_pids; do
            echo "PID $pid: $(ps -p $pid -o cmd=)"
        done
        
        read -p "Kill these connections? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            for pid in $ssh_pids; do
                kill -9 "$pid" 2>/dev/null
            done
            success "Killed connections from $ip"
            log_action "Killed connections from IP: $ip"
        fi
    else
        warn "No connections found from $ip"
    fi
    
    # Also block the IP
    read -p "Block this IP in firewall? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        iptables -I INPUT -s "$ip" -j DROP
        iptables -I OUTPUT -d "$ip" -j DROP
        success "Blocked $ip in firewall"
        log_action "Blocked IP: $ip"
    fi
}

#=============================================================================
# KILL SUSPICIOUS PROCESSES
#=============================================================================
kill_suspicious() {
    header "Kill Suspicious Processes"
    
    info "Processes in /tmp, /dev/shm, /var/tmp:"
    ps aux | awk '$11 ~ /^(\/tmp|\/dev\/shm|\/var\/tmp)/' | while read -r line; do
        echo "$line"
    done
    
    echo ""
    info "Processes with deleted binaries:"
    ls -la /proc/*/exe 2>/dev/null | grep deleted | while read -r line; do
        local pid=$(echo "$line" | grep -oP '/proc/\K[0-9]+')
        echo "PID $pid: $(ps -p $pid -o cmd= 2>/dev/null)"
    done
    
    echo ""
    read -p "Enter PID to kill (or 'all' for all suspicious): " target
    
    if [ "$target" == "all" ]; then
        # Kill processes in temp dirs
        for pid in $(ps aux | awk '$11 ~ /^(\/tmp|\/dev\/shm|\/var\/tmp)/ {print $2}'); do
            kill -9 "$pid" 2>/dev/null
            echo "Killed PID $pid"
        done
        
        # Kill deleted binary processes
        for pid in $(ls -la /proc/*/exe 2>/dev/null | grep deleted | grep -oP '/proc/\K[0-9]+'); do
            kill -9 "$pid" 2>/dev/null
            echo "Killed PID $pid"
        done
        
        success "Killed all suspicious processes"
        log_action "Killed all suspicious processes"
    elif [ -n "$target" ]; then
        kill -9 "$target"
        success "Killed PID $target"
        log_action "Killed PID: $target"
    fi
}

#=============================================================================
# FORCE LOGOUT ALL USERS
#=============================================================================
force_logout_all() {
    header "Force Logout ALL Users"
    
    warn "This will logout ALL users except root console!"
    
    who
    
    read -p "Proceed? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    # Keep track of current session
    local my_tty=$(tty | sed 's/\/dev\///')
    
    who | while read -r user tty rest; do
        if [ "$tty" != "$my_tty" ]; then
            pkill -9 -t "$tty"
            echo "Killed $user on $tty"
        else
            echo "Skipping own session: $tty"
        fi
    done
    
    success "Forced logout of all other users"
    log_action "Forced logout of all users"
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    echo ""
    echo "Kill Session Options:"
    echo "1) Show active sessions"
    echo "2) Kill user session (by username)"
    echo "3) Kill by TTY"
    echo "4) Kill by source IP"
    echo "5) Kill suspicious processes"
    echo "6) Force logout ALL users"
    echo ""
    read -p "Select option [1-6]: " choice
    
    case $choice in
        1) show_sessions ;;
        2) kill_user_session ;;
        3) kill_by_tty ;;
        4) kill_by_ip ;;
        5) kill_suspicious ;;
        6) force_logout_all ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
