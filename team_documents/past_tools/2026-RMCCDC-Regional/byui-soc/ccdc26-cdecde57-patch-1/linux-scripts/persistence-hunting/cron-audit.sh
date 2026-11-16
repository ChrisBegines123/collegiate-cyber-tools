#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Cron Job Audit
# Find malicious cron jobs and scheduled tasks

source "$(dirname "$0")/../utils/common.sh"
require_root

header "Cron Job Audit"

#=============================================================================
# CHECK ALL CRON LOCATIONS
#=============================================================================
audit_crontabs() {
    header "Auditing User Crontabs"
    
    # System crontab
    info "System crontab (/etc/crontab):"
    if [ -f /etc/crontab ]; then
        grep -v "^#" /etc/crontab | grep -v "^$"
    fi
    
    # Cron directories
    for dir in /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly; do
        if [ -d "$dir" ]; then
            info "Contents of $dir:"
            ls -la "$dir"
            echo ""
            for file in "$dir"/*; do
                if [ -f "$file" ]; then
                    echo "--- $file ---"
                    cat "$file"
                    echo ""
                fi
            done
        fi
    done
    
    # User crontabs
    info "User crontabs:"
    for user in $(cut -d: -f1 /etc/passwd); do
        local crontab=$(crontab -l -u "$user" 2>/dev/null)
        if [ -n "$crontab" ]; then
            warn "Crontab for $user:"
            echo "$crontab"
            echo ""
        fi
    done
    
    # Check crontab spool directory directly
    info "Checking crontab spool directory..."
    if [ -d /var/spool/cron/crontabs ]; then
        ls -la /var/spool/cron/crontabs/
        for f in /var/spool/cron/crontabs/*; do
            if [ -f "$f" ]; then
                echo "--- $f ---"
                cat "$f"
            fi
        done
    fi
    
    if [ -d /var/spool/cron ]; then
        ls -la /var/spool/cron/
    fi
}

#=============================================================================
# CHECK FOR SUSPICIOUS CRON ENTRIES
#=============================================================================
find_suspicious_cron() {
    header "Scanning for Suspicious Cron Entries"
    
    local suspicious_patterns=(
        "curl"
        "wget"
        "nc "
        "ncat"
        "netcat"
        "/tmp/"
        "/dev/shm/"
        "/var/tmp/"
        "base64"
        "python.*-c"
        "perl.*-e"
        "ruby.*-e"
        "bash.*-i"
        "sh.*-i"
        "| *sh"
        "| *bash"
        "chmod.*777"
        "chmod.*\+x"
        "mkfifo"
        "/dev/tcp"
        "/dev/udp"
        "0.0.0.0"
        "reverse"
        "shell"
        "payload"
        "meterpreter"
    )
    
    # Search all cron locations
    local cron_files=(
        "/etc/crontab"
        "/etc/cron.d/*"
        "/etc/cron.daily/*"
        "/etc/cron.hourly/*"
        "/etc/cron.weekly/*"
        "/etc/cron.monthly/*"
        "/var/spool/cron/crontabs/*"
        "/var/spool/cron/*"
    )
    
    for pattern in "${suspicious_patterns[@]}"; do
        for location in "${cron_files[@]}"; do
            for file in $location; do
                [ -f "$file" ] || continue
                if grep -l "$pattern" "$file" 2>/dev/null; then
                    log_finding "Suspicious pattern '$pattern' in: $file"
                    grep -n "$pattern" "$file"
                fi
            done
        done
    done
    
    # Check user crontabs
    for user in $(cut -d: -f1 /etc/passwd); do
        local crontab=$(crontab -l -u "$user" 2>/dev/null)
        if [ -n "$crontab" ]; then
            for pattern in "${suspicious_patterns[@]}"; do
                if echo "$crontab" | grep -q "$pattern"; then
                    log_finding "Suspicious pattern '$pattern' in crontab for: $user"
                fi
            done
        fi
    done
}

#=============================================================================
# CHECK AT JOBS
#=============================================================================
audit_at_jobs() {
    header "Auditing AT Jobs"
    
    if command -v atq &>/dev/null; then
        info "Queued at jobs:"
        atq
        
        # Show content of each at job
        for job in $(atq | awk '{print $1}'); do
            echo "--- Job $job ---"
            at -c "$job" 2>/dev/null | tail -20
        done
    else
        info "at command not available"
    fi
    
    # Check at spool
    if [ -d /var/spool/at ]; then
        info "AT spool directory:"
        ls -la /var/spool/at/
    fi
}

#=============================================================================
# CHECK ANACRON
#=============================================================================
audit_anacron() {
    header "Auditing Anacron"
    
    if [ -f /etc/anacrontab ]; then
        info "Anacrontab contents:"
        cat /etc/anacrontab
    fi
}

#=============================================================================
# CHECK SYSTEMD TIMERS
#=============================================================================
audit_systemd_timers() {
    header "Auditing Systemd Timers"
    
    if [ "$INIT_SYSTEM" == "systemd" ]; then
        info "Active timers:"
        systemctl list-timers --all --no-pager
        
        # Check for custom timers
        info "Custom timer units:"
        for timer in /etc/systemd/system/*.timer; do
            [ -f "$timer" ] || continue
            warn "Found custom timer: $timer"
            cat "$timer"
            
            # Get associated service
            local service="${timer%.timer}.service"
            if [ -f "$service" ]; then
                echo "--- Associated service: $service ---"
                cat "$service"
            fi
        done
        
        # Check user timers
        for user_dir in /home/*/.config/systemd/user /root/.config/systemd/user; do
            if [ -d "$user_dir" ]; then
                for timer in "$user_dir"/*.timer; do
                    [ -f "$timer" ] || continue
                    log_finding "User timer found: $timer"
                    cat "$timer"
                done
            fi
        done
    fi
}

#=============================================================================
# CLEAN MALICIOUS CRON
#=============================================================================
clean_cron() {
    header "Cleaning Cron Jobs"
    
    warn "This will help you remove suspicious cron entries."
    
    # List all and prompt for removal
    for user in $(cut -d: -f1 /etc/passwd); do
        local crontab=$(crontab -l -u "$user" 2>/dev/null)
        if [ -n "$crontab" ]; then
            warn "Crontab for $user:"
            echo "$crontab"
            read -p "Clear entire crontab for $user? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                crontab -r -u "$user"
                success "Cleared crontab for $user"
                log_action "Cleared crontab for $user"
            fi
        fi
    done
    
    # Check cron.d for suspicious files
    info "Checking /etc/cron.d for suspicious files..."
    for file in /etc/cron.d/*; do
        [ -f "$file" ] || continue
        warn "Found: $file"
        cat "$file"
        read -p "Remove $file? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -f "$file"
            success "Removed: $file"
            log_action "Removed cron file: $file"
        fi
    done
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    echo ""
    echo "Cron Audit Options:"
    echo "1) Audit all crontabs"
    echo "2) Find suspicious cron entries"
    echo "3) Audit at jobs"
    echo "4) Audit anacron"
    echo "5) Audit systemd timers"
    echo "6) Clean malicious cron jobs"
    echo "7) Run ALL audits"
    echo ""
    read -p "Select option [1-7]: " choice
    
    case $choice in
        1) audit_crontabs ;;
        2) find_suspicious_cron ;;
        3) audit_at_jobs ;;
        4) audit_anacron ;;
        5) audit_systemd_timers ;;
        6) clean_cron ;;
        7)
            audit_crontabs
            find_suspicious_cron
            audit_at_jobs
            audit_anacron
            audit_systemd_timers
            ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
