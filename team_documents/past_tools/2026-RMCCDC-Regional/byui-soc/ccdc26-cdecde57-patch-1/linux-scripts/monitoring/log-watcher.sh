#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Log Watcher
# Real-time log analysis for security events

source "$(dirname "$0")/../utils/common.sh"
require_root

header "Log Watcher"

#=============================================================================
# LOG FILES TO MONITOR
#=============================================================================
LOG_FILES=(
    "/var/log/auth.log"
    "/var/log/secure"
    "/var/log/syslog"
    "/var/log/messages"
    "/var/log/audit/audit.log"
    "/var/log/kern.log"
    "/var/log/apache2/access.log"
    "/var/log/apache2/error.log"
    "/var/log/nginx/access.log"
    "/var/log/nginx/error.log"
    "/var/log/httpd/access_log"
    "/var/log/httpd/error_log"
    "/var/log/mysql/error.log"
    "/var/log/postgresql/postgresql.log"
)

#=============================================================================
# SUSPICIOUS PATTERNS
#=============================================================================
SUSPICIOUS_PATTERNS=(
    "Failed password"
    "authentication failure"
    "BREAK-IN ATTEMPT"
    "Invalid user"
    "Illegal user"
    "Connection closed by.*port 22.*preauth"
    "Did not receive identification"
    "Bad protocol version"
    "reverse mapping"
    "session opened for user root"
    "sudo:.*COMMAND="
    "su:.*to root"
    "CRON.*CMD"
    "Accepted password"
    "Accepted publickey"
    "segfault"
    "kernel panic"
    "Out of memory"
    "oom-killer"
    "error"
    "warning"
    "critical"
    "alert"
)

#=============================================================================
# FIND AVAILABLE LOGS
#=============================================================================
find_logs() {
    header "Available Log Files"
    
    for log in "${LOG_FILES[@]}"; do
        if [ -f "$log" ]; then
            local size=$(du -h "$log" | awk '{print $1}')
            success "$log ($size)"
        fi
    done
    
    echo ""
    info "Journald logs:"
    journalctl --disk-usage 2>/dev/null
}

#=============================================================================
# CHECK AUTH LOGS
#=============================================================================
check_auth_logs() {
    header "Authentication Logs"
    
    local auth_log=""
    [ -f /var/log/auth.log ] && auth_log="/var/log/auth.log"
    [ -f /var/log/secure ] && auth_log="/var/log/secure"
    
    if [ -z "$auth_log" ]; then
        # Try journald
        info "Using journald for auth logs..."
        journalctl -u sshd --since "1 hour ago" --no-pager | tail -50
        return
    fi
    
    info "Failed login attempts (last 100):"
    grep -iE "(failed|failure|invalid|illegal)" "$auth_log" | tail -100
    
    echo ""
    info "Successful logins (last 50):"
    grep -iE "(accepted|session opened)" "$auth_log" | tail -50
    
    echo ""
    info "Sudo commands (last 50):"
    grep "sudo:" "$auth_log" | grep "COMMAND" | tail -50
    
    echo ""
    info "Login summary by user:"
    grep "session opened" "$auth_log" | awk '{for(i=1;i<=NF;i++)if($i~/user/){print $(i+1)}}' | sort | uniq -c | sort -rn | head -20
    
    echo ""
    info "Failed login IPs:"
    grep -iE "(failed|invalid)" "$auth_log" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort | uniq -c | sort -rn | head -20
}

#=============================================================================
# CHECK SYSTEM LOGS
#=============================================================================
check_system_logs() {
    header "System Logs"
    
    local syslog=""
    [ -f /var/log/syslog ] && syslog="/var/log/syslog"
    [ -f /var/log/messages ] && syslog="/var/log/messages"
    
    if [ -z "$syslog" ]; then
        info "Using journald..."
        journalctl --since "1 hour ago" --no-pager | tail -100
        return
    fi
    
    info "Recent errors and warnings:"
    grep -iE "(error|warning|critical|alert|emergency)" "$syslog" | tail -50
    
    echo ""
    info "Kernel messages:"
    grep "kernel:" "$syslog" | tail -30
}

#=============================================================================
# WATCH LOGS IN REAL-TIME
#=============================================================================
watch_logs() {
    header "Real-Time Log Monitoring"
    
    # Build list of existing logs
    local watch_logs=()
    for log in "${LOG_FILES[@]}"; do
        [ -f "$log" ] && watch_logs+=("$log")
    done
    
    if [ ${#watch_logs[@]} -eq 0 ]; then
        info "No standard logs found, using journald..."
        journalctl -f
        return
    fi
    
    info "Watching: ${watch_logs[*]}"
    info "Highlighting suspicious patterns. Press Ctrl+C to stop."
    
    tail -f "${watch_logs[@]}" 2>/dev/null | while read -r line; do
        local highlighted=false
        for pattern in "${SUSPICIOUS_PATTERNS[@]}"; do
            if echo "$line" | grep -qi "$pattern"; then
                echo -e "${RED}[ALERT]${NC} $line"
                highlighted=true
                break
            fi
        done
        $highlighted || echo "$line"
    done
}

#=============================================================================
# SEARCH LOGS
#=============================================================================
search_logs() {
    header "Search Logs"
    
    read -p "Enter search pattern: " pattern
    [ -z "$pattern" ] && return
    
    read -p "Time range (e.g., '1 hour ago', '2024-01-01'): " timerange
    
    info "Searching for: $pattern"
    
    # Search files
    for log in "${LOG_FILES[@]}"; do
        if [ -f "$log" ]; then
            local matches=$(grep -c "$pattern" "$log" 2>/dev/null)
            if [ "$matches" -gt 0 ]; then
                warn "Found $matches matches in $log:"
                grep -n "$pattern" "$log" | head -20
                echo ""
            fi
        fi
    done
    
    # Search journald
    if [ -n "$timerange" ]; then
        info "Journald results:"
        journalctl --since "$timerange" --no-pager | grep "$pattern" | head -50
    fi
}

#=============================================================================
# CHECK FOR LOG TAMPERING
#=============================================================================
check_log_tampering() {
    header "Checking for Log Tampering"
    
    info "Log file permissions:"
    for log in "${LOG_FILES[@]}"; do
        if [ -f "$log" ]; then
            ls -la "$log"
            
            # Check for unusual permissions
            local perms=$(stat -c %a "$log")
            if [ "$perms" != "640" ] && [ "$perms" != "644" ] && [ "$perms" != "600" ]; then
                warn "Unusual permissions on $log: $perms"
            fi
        fi
    done
    
    echo ""
    info "Checking for gaps in logs..."
    local auth_log=""
    [ -f /var/log/auth.log ] && auth_log="/var/log/auth.log"
    [ -f /var/log/secure ] && auth_log="/var/log/secure"
    
    if [ -n "$auth_log" ]; then
        # Look for time gaps > 1 hour
        awk '{print $1, $2, $3}' "$auth_log" | uniq -c | while read -r count date; do
            [ "$count" -lt 5 ] && warn "Sparse logging around: $date"
        done
    fi
    
    echo ""
    info "Checking log rotation:"
    ls -la /var/log/*.gz /var/log/*.1 2>/dev/null | head -20
    
    echo ""
    info "Checking wtmp/btmp integrity:"
    [ -f /var/log/wtmp ] && last -10
    [ -f /var/log/btmp ] && lastb -10 2>/dev/null
}

#=============================================================================
# EXPORT LOGS
#=============================================================================
export_logs() {
    header "Export Logs"
    
    local export_dir="/tmp/logs-export-$(timestamp)"
    mkdir -p "$export_dir"
    
    info "Exporting logs to $export_dir..."
    
    for log in "${LOG_FILES[@]}"; do
        if [ -f "$log" ]; then
            cp "$log" "$export_dir/"
        fi
    done
    
    # Export journald
    journalctl --since "24 hours ago" > "$export_dir/journald-24h.log" 2>/dev/null
    
    # Export last/lastb
    last > "$export_dir/last.log" 2>/dev/null
    lastb > "$export_dir/lastb.log" 2>/dev/null
    
    # Create tarball
    tar -czf "${export_dir}.tar.gz" -C /tmp "$(basename "$export_dir")"
    rm -rf "$export_dir"
    
    success "Logs exported to: ${export_dir}.tar.gz"
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    echo ""
    echo "Log Watcher Options:"
    echo "1) Find available logs"
    echo "2) Check authentication logs"
    echo "3) Check system logs"
    echo "4) Watch logs in real-time"
    echo "5) Search logs"
    echo "6) Check for log tampering"
    echo "7) Export logs"
    echo ""
    read -p "Select option [1-7]: " choice
    
    case $choice in
        1) find_logs ;;
        2) check_auth_logs ;;
        3) check_system_logs ;;
        4) watch_logs ;;
        5) search_logs ;;
        6) check_log_tampering ;;
        7) export_logs ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
