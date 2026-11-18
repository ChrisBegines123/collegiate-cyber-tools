#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Process Monitor
# Monitor for suspicious processes and connections

source "$(dirname "$0")/../utils/common.sh"
require_root

header "Process Monitor"

SUSPICIOUS_NAMES=("nc" "ncat" "netcat" "socat" "xmrig" "miner" "backdoor" "reverse" "shell" "meterpreter" "beacon")

#=============================================================================
# LIST ALL PROCESSES
#=============================================================================
list_processes() {
    header "All Running Processes"
    ps auxf --sort=-%cpu | head -50
}

#=============================================================================
# FIND SUSPICIOUS PROCESSES
#=============================================================================
find_suspicious() {
    header "Scanning for Suspicious Processes"
    
    info "Checking process names..."
    for name in "${SUSPICIOUS_NAMES[@]}"; do
        pgrep -af "$name" 2>/dev/null | while read -r line; do
            log_finding "Suspicious process '$name': $line"
        done
    done
    
    info "Checking for processes in /tmp, /dev/shm..."
    ps aux | awk '{print $11}' | grep -E '^(/tmp/|/var/tmp/|/dev/shm/)' | while read -r cmd; do
        log_finding "Process in temp dir: $cmd"
    done
    
    info "Checking for processes with deleted binaries..."
    ls -la /proc/*/exe 2>/dev/null | grep deleted | while read -r line; do
        log_finding "Deleted binary: $line"
    done
    
    info "Checking for shells spawned by web processes..."
    ps -eo pid,ppid,user,cmd | grep -E '(bash|sh|zsh)' | while read -r pid ppid user cmd; do
        local parent_cmd=$(ps -p "$ppid" -o cmd= 2>/dev/null)
        if echo "$parent_cmd" | grep -qiE '(apache|nginx|httpd|php|python|perl|java|node)'; then
            log_finding "Shell from web process: PID=$pid PPID=$ppid"
        fi
    done
}

#=============================================================================
# MONITOR NEW PROCESSES
#=============================================================================
monitor_processes() {
    header "Monitoring New Processes"
    info "Press Ctrl+C to stop."
    
    local prev_pids=$(ps -eo pid | sort -n)
    
    while true; do
        sleep 2
        local curr_pids=$(ps -eo pid | sort -n)
        local new_pids=$(comm -13 <(echo "$prev_pids") <(echo "$curr_pids"))
        
        for pid in $new_pids; do
            if [ -d "/proc/$pid" ]; then
                local cmd=$(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ')
                local user=$(ps -p "$pid" -o user= 2>/dev/null)
                [ -n "$cmd" ] && echo -e "${CYAN}[NEW]${NC} PID=$pid USER=$user CMD=$cmd"
            fi
        done
        prev_pids="$curr_pids"
    done
}

#=============================================================================
# CHECK PROCESS CONNECTIONS
#=============================================================================
check_connections() {
    header "Process Network Connections"
    
    info "Established connections:"
    get_established_connections
    
    echo ""
    info "Listening ports:"
    get_listening_ports
}

#=============================================================================
# KILL PROCESS
#=============================================================================
kill_process() {
    header "Kill Process"
    
    read -p "Enter PID to kill: " pid
    [ -z "$pid" ] && return
    
    ps -p "$pid" -o pid,ppid,user,cmd
    
    read -p "Kill? (y/n): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && kill -9 "$pid" && success "Killed PID $pid"
}

#=============================================================================
# CHECK HIDDEN PROCESSES
#=============================================================================
check_hidden_processes() {
    header "Checking for Hidden Processes"
    
    local ps_pids=$(ps -eo pid | grep -v PID | sort -n)
    local proc_pids=$(ls -d /proc/[0-9]* 2>/dev/null | cut -d/ -f3 | sort -n)
    local hidden=$(comm -23 <(echo "$proc_pids") <(echo "$ps_pids"))
    
    if [ -n "$hidden" ]; then
        for pid in $hidden; do
            [ -d "/proc/$pid" ] && log_finding "Hidden process: PID=$pid"
        done
    else
        success "No hidden processes detected"
    fi
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    echo ""
    echo "Process Monitor Options:"
    echo "1) List all processes"
    echo "2) Find suspicious processes"
    echo "3) Monitor new processes (live)"
    echo "4) Check process connections"
    echo "5) Check for hidden processes"
    echo "6) Kill a process"
    echo ""
    read -p "Select option [1-6]: " choice
    
    case $choice in
        1) list_processes ;;
        2) find_suspicious ;;
        3) monitor_processes ;;
        4) check_connections ;;
        5) check_hidden_processes ;;
        6) kill_process ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
