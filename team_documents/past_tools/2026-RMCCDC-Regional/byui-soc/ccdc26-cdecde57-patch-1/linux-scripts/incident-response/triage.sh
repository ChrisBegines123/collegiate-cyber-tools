#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Incident Triage
# Quick assessment of system state during incident

source "$(dirname "$0")/../utils/common.sh"
require_root

header "Incident Triage"

TRIAGE_DIR="/tmp/triage-$(timestamp)"
mkdir -p "$TRIAGE_DIR"

#=============================================================================
# QUICK ASSESSMENT
#=============================================================================
quick_assessment() {
    header "Quick Assessment"
    
    echo "=== SYSTEM INFO ===" | tee "$TRIAGE_DIR/assessment.txt"
    echo "Hostname: $(hostname)" | tee -a "$TRIAGE_DIR/assessment.txt"
    echo "Date: $(date)" | tee -a "$TRIAGE_DIR/assessment.txt"
    echo "Uptime: $(uptime)" | tee -a "$TRIAGE_DIR/assessment.txt"
    echo "Kernel: $(uname -a)" | tee -a "$TRIAGE_DIR/assessment.txt"
    echo "" | tee -a "$TRIAGE_DIR/assessment.txt"
    
    echo "=== LOGGED IN USERS ===" | tee -a "$TRIAGE_DIR/assessment.txt"
    who | tee -a "$TRIAGE_DIR/assessment.txt"
    echo "" | tee -a "$TRIAGE_DIR/assessment.txt"
    
    echo "=== RECENT LOGINS ===" | tee -a "$TRIAGE_DIR/assessment.txt"
    last -20 | tee -a "$TRIAGE_DIR/assessment.txt"
    echo "" | tee -a "$TRIAGE_DIR/assessment.txt"
    
    echo "=== LISTENING PORTS ===" | tee -a "$TRIAGE_DIR/assessment.txt"
    get_listening_ports | tee -a "$TRIAGE_DIR/assessment.txt"
    echo "" | tee -a "$TRIAGE_DIR/assessment.txt"
    
    echo "=== ESTABLISHED CONNECTIONS ===" | tee -a "$TRIAGE_DIR/assessment.txt"
    get_established_connections | tee -a "$TRIAGE_DIR/assessment.txt"
    echo "" | tee -a "$TRIAGE_DIR/assessment.txt"
    
    echo "=== TOP PROCESSES ===" | tee -a "$TRIAGE_DIR/assessment.txt"
    ps aux --sort=-%cpu | head -20 | tee -a "$TRIAGE_DIR/assessment.txt"
    echo "" | tee -a "$TRIAGE_DIR/assessment.txt"
    
    echo "=== PROCESS TREE ===" | tee -a "$TRIAGE_DIR/assessment.txt"
    ps auxf | head -50 | tee -a "$TRIAGE_DIR/assessment.txt"
    
    success "Quick assessment saved to $TRIAGE_DIR/assessment.txt"
}

#=============================================================================
# FIND ACTIVE ATTACKERS
#=============================================================================
find_attackers() {
    header "Finding Active Attackers"
    
    info "Current logged-in users:"
    who -a
    
    echo ""
    info "User sessions with PTY:"
    ps aux | grep -E '(pts/|tty)' | grep -v grep
    
    echo ""
    info "SSH connections:"
    ss -tnp | grep :22 | grep ESTAB
    
    echo ""
    info "Recent successful logins:"
    grep -E "(Accepted|session opened)" /var/log/auth.log /var/log/secure 2>/dev/null | tail -20
    
    echo ""
    info "Active shells by user:"
    ps -eo user,pid,tty,cmd | grep -E '(bash|sh|zsh)' | grep -v grep
}

#=============================================================================
# CHECK RUNNING MALWARE
#=============================================================================
check_malware() {
    header "Checking for Active Malware"
    
    info "Processes in /tmp, /dev/shm, /var/tmp:"
    ps aux | awk '$11 ~ /^(\/tmp|\/dev\/shm|\/var\/tmp)/' | tee "$TRIAGE_DIR/suspicious-processes.txt"
    
    echo ""
    info "Processes with deleted binaries:"
    ls -la /proc/*/exe 2>/dev/null | grep deleted | tee -a "$TRIAGE_DIR/suspicious-processes.txt"
    
    echo ""
    info "Network connections by suspicious processes:"
    for pid in $(ps aux | awk '$11 ~ /^(\/tmp|\/dev\/shm|\/var\/tmp)/ {print $2}'); do
        echo "PID $pid connections:"
        ls -la /proc/$pid/fd 2>/dev/null | grep socket
    done | tee -a "$TRIAGE_DIR/suspicious-processes.txt"
    
    echo ""
    info "Reverse shell indicators:"
    ss -tnp | grep -E '(4444|5555|6666|7777|8888|9999|1234|31337)'
}

#=============================================================================
# COLLECT VOLATILE DATA
#=============================================================================
collect_volatile() {
    header "Collecting Volatile Data"
    
    info "Saving process list..."
    ps auxf > "$TRIAGE_DIR/processes.txt"
    
    info "Saving network connections..."
    ss -tunapl > "$TRIAGE_DIR/network-connections.txt"
    
    info "Saving routing table..."
    ip route > "$TRIAGE_DIR/routes.txt"
    
    info "Saving ARP table..."
    ip neigh > "$TRIAGE_DIR/arp.txt"
    
    info "Saving open files..."
    lsof -n > "$TRIAGE_DIR/open-files.txt" 2>/dev/null
    
    info "Saving memory info..."
    cat /proc/meminfo > "$TRIAGE_DIR/meminfo.txt"
    
    info "Saving loaded modules..."
    lsmod > "$TRIAGE_DIR/modules.txt"
    
    info "Saving environment..."
    env > "$TRIAGE_DIR/environment.txt"
    
    info "Saving mount points..."
    mount > "$TRIAGE_DIR/mounts.txt"
    
    success "Volatile data collected in $TRIAGE_DIR/"
}

#=============================================================================
# TIMELINE OF RECENT ACTIVITY
#=============================================================================
create_timeline() {
    header "Creating Activity Timeline"
    
    local timeline="$TRIAGE_DIR/timeline.txt"
    
    echo "=== TIMELINE OF RECENT ACTIVITY ===" > "$timeline"
    echo "Generated: $(date)" >> "$timeline"
    echo "" >> "$timeline"
    
    # Recent file modifications
    echo "=== Files modified in last 24 hours ===" >> "$timeline"
    find /etc /var /home /root /tmp -type f -mtime -1 2>/dev/null | head -100 >> "$timeline"
    
    echo "" >> "$timeline"
    echo "=== Recent auth events ===" >> "$timeline"
    grep -h "" /var/log/auth.log /var/log/secure 2>/dev/null | tail -100 >> "$timeline"
    
    echo "" >> "$timeline"
    echo "=== Recent cron activity ===" >> "$timeline"
    grep -h CRON /var/log/syslog /var/log/messages /var/log/cron 2>/dev/null | tail -50 >> "$timeline"
    
    echo "" >> "$timeline"
    echo "=== Bash history (all users) ===" >> "$timeline"
    for home in /home/* /root; do
        if [ -f "$home/.bash_history" ]; then
            echo "--- $home/.bash_history ---" >> "$timeline"
            tail -50 "$home/.bash_history" >> "$timeline"
        fi
    done
    
    success "Timeline saved to $timeline"
}

#=============================================================================
# IDENTIFY COMPROMISED ACCOUNTS
#=============================================================================
identify_compromised_accounts() {
    header "Identifying Potentially Compromised Accounts"
    
    info "Accounts logged in from multiple IPs:"
    local auth_log=$([ -f /var/log/auth.log ] && echo /var/log/auth.log || echo /var/log/secure)
    [ -f "$auth_log" ] && grep "Accepted" "$auth_log" | awk '{for(i=1;i<=NF;i++)if($i=="from")print $(i-2), $(i+1)}' | sort | uniq -c | sort -rn | head -20
    
    echo ""
    info "Users with recent password changes:"
    for user in $(cut -d: -f1 /etc/passwd); do
        local lastchange=$(chage -l "$user" 2>/dev/null | grep "Last password change" | cut -d: -f2)
        [ -n "$lastchange" ] && echo "$user: $lastchange"
    done | head -20
    
    echo ""
    info "Users with SSH keys added recently:"
    find /home -name "authorized_keys" -mtime -7 2>/dev/null
    find /root -name "authorized_keys" -mtime -7 2>/dev/null
}

#=============================================================================
# PACKAGE TRIAGE RESULTS
#=============================================================================
package_results() {
    header "Packaging Triage Results"
    
    local tarball="/tmp/triage-$(hostname)-$(timestamp).tar.gz"
    
    tar -czf "$tarball" -C /tmp "$(basename "$TRIAGE_DIR")"
    
    success "Triage package: $tarball"
    info "Size: $(du -h "$tarball" | awk '{print $1}')"
}

#=============================================================================
# FULL TRIAGE
#=============================================================================
full_triage() {
    quick_assessment
    find_attackers
    check_malware
    collect_volatile
    create_timeline
    identify_compromised_accounts
    package_results
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    echo ""
    echo "Triage output directory: $TRIAGE_DIR"
    echo ""
    echo "Incident Triage Options:"
    echo "1) Quick assessment"
    echo "2) Find active attackers"
    echo "3) Check for running malware"
    echo "4) Collect volatile data"
    echo "5) Create activity timeline"
    echo "6) Identify compromised accounts"
    echo "7) Package triage results"
    echo "8) FULL TRIAGE (all of the above)"
    echo ""
    read -p "Select option [1-8]: " choice
    
    case $choice in
        1) quick_assessment ;;
        2) find_attackers ;;
        3) check_malware ;;
        4) collect_volatile ;;
        5) create_timeline ;;
        6) identify_compromised_accounts ;;
        7) package_results ;;
        8) full_triage ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
