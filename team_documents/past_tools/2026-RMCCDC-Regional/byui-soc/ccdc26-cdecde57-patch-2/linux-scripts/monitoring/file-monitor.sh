#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - File Integrity Monitor
# Monitor critical files for changes

source "$(dirname "$0")/../utils/common.sh"
require_root

header "File Integrity Monitor"

BASELINE_DIR="/var/lib/ccdc-toolkit/baseline"
mkdir -p "$BASELINE_DIR"

#=============================================================================
# CRITICAL FILES TO MONITOR
#=============================================================================
CRITICAL_FILES=(
    "/etc/passwd"
    "/etc/shadow"
    "/etc/group"
    "/etc/gshadow"
    "/etc/sudoers"
    "/etc/ssh/sshd_config"
    "/etc/hosts"
    "/etc/hosts.allow"
    "/etc/hosts.deny"
    "/etc/crontab"
    "/etc/profile"
    "/etc/bashrc"
    "/etc/bash.bashrc"
    "/etc/pam.d/sshd"
    "/etc/pam.d/sudo"
    "/etc/pam.d/su"
    "/etc/ld.so.preload"
    "/etc/ld.so.conf"
    "/etc/resolv.conf"
    "/etc/nsswitch.conf"
    "/root/.bashrc"
    "/root/.profile"
    "/root/.ssh/authorized_keys"
)

CRITICAL_DIRS=(
    "/etc/cron.d"
    "/etc/cron.daily"
    "/etc/cron.hourly"
    "/etc/sudoers.d"
    "/etc/systemd/system"
    "/etc/profile.d"
    "/etc/pam.d"
)

#=============================================================================
# CREATE BASELINE
#=============================================================================
create_baseline() {
    header "Creating Baseline"
    
    local baseline_file="$BASELINE_DIR/baseline-$(timestamp).txt"
    
    > "$baseline_file"
    
    # Hash individual files
    for file in "${CRITICAL_FILES[@]}"; do
        if [ -f "$file" ]; then
            local hash=$(hash_file "$file")
            local perms=$(stat -c '%a %U:%G' "$file" 2>/dev/null)
            echo "FILE|$file|$hash|$perms" >> "$baseline_file"
        fi
    done
    
    # Hash directory contents
    for dir in "${CRITICAL_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            find "$dir" -type f 2>/dev/null | while read -r file; do
                local hash=$(hash_file "$file")
                local perms=$(stat -c '%a %U:%G' "$file" 2>/dev/null)
                echo "FILE|$file|$hash|$perms" >> "$baseline_file"
            done
        fi
    done
    
    # Record directory listings
    for dir in "${CRITICAL_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            echo "DIR|$dir|$(ls -la "$dir" 2>/dev/null | md5sum | awk '{print $1}')" >> "$baseline_file"
        fi
    done
    
    # Create symlink to current baseline
    ln -sf "$baseline_file" "$BASELINE_DIR/current"
    
    success "Baseline created: $baseline_file"
    info "$(wc -l < "$baseline_file") entries recorded"
    log_action "Created file integrity baseline"
}

#=============================================================================
# CHECK AGAINST BASELINE
#=============================================================================
check_baseline() {
    header "Checking Against Baseline"
    
    local baseline_file="$BASELINE_DIR/current"
    
    if [ ! -f "$baseline_file" ]; then
        error "No baseline found. Run 'create baseline' first."
        return 1
    fi
    
    local changes=0
    
    while IFS='|' read -r type path hash perms; do
        case "$type" in
            FILE)
                if [ ! -f "$path" ]; then
                    log_finding "FILE DELETED: $path"
                    ((changes++))
                else
                    local current_hash=$(hash_file "$path")
                    local current_perms=$(stat -c '%a %U:%G' "$path" 2>/dev/null)
                    
                    if [ "$current_hash" != "$hash" ]; then
                        log_finding "FILE MODIFIED: $path"
                        log_finding "  Old hash: $hash"
                        log_finding "  New hash: $current_hash"
                        ((changes++))
                    fi
                    
                    if [ "$current_perms" != "$perms" ]; then
                        log_finding "PERMISSIONS CHANGED: $path"
                        log_finding "  Old: $perms"
                        log_finding "  New: $current_perms"
                        ((changes++))
                    fi
                fi
                ;;
            DIR)
                if [ -d "$path" ]; then
                    local current_hash=$(ls -la "$path" 2>/dev/null | md5sum | awk '{print $1}')
                    if [ "$current_hash" != "$hash" ]; then
                        log_finding "DIRECTORY CHANGED: $path"
                        ((changes++))
                    fi
                fi
                ;;
        esac
    done < "$baseline_file"
    
    # Check for new files in monitored directories
    for dir in "${CRITICAL_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            find "$dir" -type f 2>/dev/null | while read -r file; do
                if ! grep -q "FILE|$file|" "$baseline_file"; then
                    log_finding "NEW FILE: $file"
                    ((changes++))
                fi
            done
        fi
    done
    
    if [ $changes -eq 0 ]; then
        success "No changes detected"
    else
        warn "$changes change(s) detected"
    fi
    
    return $changes
}

#=============================================================================
# CONTINUOUS MONITORING
#=============================================================================
monitor_continuous() {
    header "Starting Continuous Monitoring"
    
    if ! command -v inotifywait &>/dev/null; then
        info "Installing inotify-tools..."
        pkg_install inotify-tools
    fi
    
    if ! command -v inotifywait &>/dev/null; then
        error "Cannot install inotify-tools, falling back to polling"
        monitor_polling
        return
    fi
    
    info "Press Ctrl+C to stop monitoring"
    
    # Build watch list
    local watch_list=""
    for file in "${CRITICAL_FILES[@]}"; do
        [ -f "$file" ] && watch_list="$watch_list $file"
    done
    for dir in "${CRITICAL_DIRS[@]}"; do
        [ -d "$dir" ] && watch_list="$watch_list $dir"
    done
    
    # Start monitoring
    inotifywait -m -e modify,create,delete,attrib --format '%T %w%f %e' --timefmt '%Y-%m-%d %H:%M:%S' $watch_list 2>/dev/null | while read -r line; do
        echo -e "${RED}[ALERT]${NC} $line"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] FILE CHANGE: $line" >> "$LOG_DIR/file-changes.log"
    done
}

#=============================================================================
# POLLING-BASED MONITORING
#=============================================================================
monitor_polling() {
    header "Starting Polling-Based Monitoring"
    
    info "Checking every 30 seconds. Press Ctrl+C to stop."
    
    while true; do
        check_baseline > /dev/null
        sleep 30
    done
}

#=============================================================================
# SHOW BASELINE
#=============================================================================
show_baseline() {
    header "Current Baseline"
    
    local baseline_file="$BASELINE_DIR/current"
    
    if [ ! -f "$baseline_file" ]; then
        error "No baseline found"
        return 1
    fi
    
    info "Baseline file: $(readlink -f "$baseline_file")"
    info "Created: $(stat -c %y "$baseline_file" 2>/dev/null)"
    info "Entries: $(wc -l < "$baseline_file")"
    echo ""
    
    head -50 "$baseline_file"
    
    local total=$(wc -l < "$baseline_file")
    if [ "$total" -gt 50 ]; then
        echo "... ($((total - 50)) more entries)"
    fi
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    echo ""
    echo "File Integrity Monitor Options:"
    echo "1) Create baseline"
    echo "2) Check against baseline"
    echo "3) Start continuous monitoring (inotify)"
    echo "4) Start polling-based monitoring"
    echo "5) Show current baseline"
    echo ""
    read -p "Select option [1-5]: " choice
    
    case $choice in
        1) create_baseline ;;
        2) check_baseline ;;
        3) monitor_continuous ;;
        4) monitor_polling ;;
        5) show_baseline ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
