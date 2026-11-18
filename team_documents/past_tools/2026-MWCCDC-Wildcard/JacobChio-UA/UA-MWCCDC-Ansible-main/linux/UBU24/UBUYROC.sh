#!/bin/bash

set -euo pipefail

###############################################################################
# Malicious Crontab & Persistence Detection Script - Ubuntu Server 24 LTS
# Scans system for suspicious scheduled tasks and persistence mechanisms
# Optimized for: Ubuntu Server 24 LTS (Noble Numbat)
# Compatibility: Ubuntu 24.04 LTS and later
###############################################################################

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
SUSPICIOUS_FOUND=0
TOTAL_CHECKED=0

# Ubuntu 24 Detection
UBUNTU_24_VERIFIED=false

# Helper functions
log_info() { echo -e "${BLUE}[+]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; }

# Verify Ubuntu 24 LTS
verify_ubuntu_24() {
    if [[ -f /etc/os-release ]]; then
        # Check for Ubuntu 24.04 LTS (Noble Numbat)
        if grep -qE "VERSION_CODENAME=noble|VERSION_ID=\"24\.04\"" /etc/os-release; then
            UBUNTU_24_VERIFIED=true
            log_success "Ubuntu Server 24 LTS (Noble Numbat) detected"
            return 0
        else
            log_warn "WARNING: System is not Ubuntu Server 24 LTS"
            # Check actual version
            local version_id=$(grep "VERSION_ID=" /etc/os-release | cut -d'"' -f2)
            local version_name=$(grep "VERSION_CODENAME=" /etc/os-release | cut -d'=' -f2)
            log_warn "Detected: Ubuntu $version_id ($version_name)"
            log_warn "This script is optimized for Ubuntu 24.04 LTS - compatibility may vary"
            
            # Still allow execution on Ubuntu/Debian
            if grep -qiE "ubuntu|debian" /etc/os-release; then
                log_info "Debian-based system detected; proceeding with caution"
                return 0
            else
                log_error "Non-Ubuntu system detected - script may not function correctly"
                return 1
            fi
        fi
    else
        log_error "Cannot detect OS version - /etc/os-release not found"
        return 1
    fi
    return 0
}

# Common malicious patterns to detect
MALICIOUS_PATTERNS=(
    "nc -l"                    # Netcat listener
    "bash -i"                  # Reverse shell
    "/dev/tcp\|/dev/udp"       # Bash network redirection
    "wget.*|curl.*pipe"        # Download and execute
    "base64.*decode"           # Encoded payload
    "eval\|exec"               # Code execution
    "rm -rf\|dd if=/dev/zero" # Destructive commands
    "\$\(\|backtick"           # Subshell execution
    "python.*socket"           # Python backdoor
    "perl.*socket"             # Perl backdoor
    "ruby.*socket"             # Ruby backdoor
    "python -c"                # Inline python execution
    "nohup.*&"                 # Background persistence
    ">/dev/null"               # Output suppression
    "crontab -"                # Crontab injection
    "at -"                     # At job injection
    "ncat\|socat"              # Alternative netcat tools
    "telnet.*-l"               # Telnet backdoor
    "ssh.*-f"                  # SSH connection spawning
)

###############################################################################
# Check System Crontabs
###############################################################################
check_system_crontabs() {
    log_info "Checking system crontabs..."
    
    local cron_files=(
        "/etc/crontab"
        "/etc/cron.d"
        "/etc/cron.hourly"
        "/etc/cron.daily"
        "/etc/cron.weekly"
        "/etc/cron.monthly"
    )
    
    for cron_location in "${cron_files[@]}"; do
        if [[ ! -e "$cron_location" ]]; then
            continue
        fi
        
        if [[ -f "$cron_location" ]]; then
            while IFS= read -r line; do
                TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
                # Skip comments and empty lines
                [[ "$line" =~ ^#.*$ ]] && continue
                [[ -z "$line" ]] && continue
                
                # Check for suspicious patterns
                for pattern in "${MALICIOUS_PATTERNS[@]}"; do
                    if echo "$line" | grep -qiE "$pattern"; then
                        log_error "SUSPICIOUS in $cron_location: $line"
                        SUSPICIOUS_FOUND=$((SUSPICIOUS_FOUND + 1))
                    fi
                done
            done < "$cron_location"
        elif [[ -d "$cron_location" ]]; then
            for file in "$cron_location"/*; do
                [[ ! -f "$file" ]] && continue
                log_info "  Checking $file..."
                while IFS= read -r line; do
                    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
                    [[ "$line" =~ ^#.*$ ]] && continue
                    [[ -z "$line" ]] && continue
                    
                    for pattern in "${MALICIOUS_PATTERNS[@]}"; do
                        if echo "$line" | grep -qiE "$pattern"; then
                            log_error "SUSPICIOUS in $file: $line"
                            SUSPICIOUS_FOUND=$((SUSPICIOUS_FOUND + 1))
                        fi
                    done
                done < "$file"
            done
        fi
    done
}

###############################################################################
# Check User Crontabs
###############################################################################
check_user_crontabs() {
    log_info "Checking user crontabs..."
    
    # Get all users with shells
    local users=$(cut -d: -f1,7 /etc/passwd | grep -v nologin | grep -v false | cut -d: -f1)
    
    for user in $users; do
        if crontab -u "$user" -l >/dev/null 2>&1; then
            log_info "  Checking crontab for user: $user"
            while IFS= read -r line; do
                TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
                [[ "$line" =~ ^#.*$ ]] && continue
                [[ -z "$line" ]] && continue
                
                for pattern in "${MALICIOUS_PATTERNS[@]}"; do
                    if echo "$line" | grep -qiE "$pattern"; then
                        log_error "SUSPICIOUS in $user crontab: $line"
                        SUSPICIOUS_FOUND=$((SUSPICIOUS_FOUND + 1))
                    fi
                done
            done < <(crontab -u "$user" -l 2>/dev/null)
        fi
    done
}

###############################################################################
# Check At Jobs
###############################################################################
check_at_jobs() {
    log_info "Checking at scheduled jobs..."
    
    if ! command -v atq >/dev/null 2>&1; then
        log_warn "atq command not found; skipping at job check"
        return
    fi
    
    # List all at jobs
    local jobs=$(atq 2>/dev/null | awk '{print $1}' || true)
    
    for job_id in $jobs; do
        log_info "  Checking at job $job_id..."
        while IFS= read -r line; do
            TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
            
            for pattern in "${MALICIOUS_PATTERNS[@]}"; do
                if echo "$line" | grep -qiE "$pattern"; then
                    log_error "SUSPICIOUS in at job $job_id: $line"
                    SUSPICIOUS_FOUND=$((SUSPICIOUS_FOUND + 1))
                fi
            done
        done < <(at -c "$job_id" 2>/dev/null || true)
    done
}

###############################################################################
# Check Systemd Services for Suspicious Timers
###############################################################################
check_systemd_timers() {
    log_info "Checking systemd timers and services..."
    
    if ! command -v systemctl >/dev/null 2>&1; then
        log_warn "systemctl not found; skipping systemd check"
        return
    fi
    
    # List all timers
    local timers=$(systemctl list-timers --all --no-pager 2>/dev/null | grep -v "^NEXT\|^--" | awk '{print $NF}' || true)
    
    for timer in $timers; do
        [[ -z "$timer" ]] && continue
        
        if systemctl cat "$timer" >/dev/null 2>&1; then
            log_info "  Checking timer: $timer"
            while IFS= read -r line; do
                TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
                [[ "$line" =~ ^#.*$ ]] && continue
                [[ -z "$line" ]] && continue
                
                for pattern in "${MALICIOUS_PATTERNS[@]}"; do
                    if echo "$line" | grep -qiE "$pattern"; then
                        log_error "SUSPICIOUS in timer $timer: $line"
                        SUSPICIOUS_FOUND=$((SUSPICIOUS_FOUND + 1))
                    fi
                done
            done < <(systemctl cat "$timer" 2>/dev/null || true)
        fi
    done
}

###############################################################################
# Check Suspicious Startup Scripts
###############################################################################
check_startup_scripts() {
    log_info "Checking startup scripts for persistence..."
    
    local startup_locations=(
        "/etc/rc.local"
        "/etc/init.d"
        "/etc/profile.d"
        "/home/*/.bashrc"
        "/home/*/.bash_profile"
        "/root/.bashrc"
        "/root/.bash_profile"
    )
    
    for location in "${startup_locations[@]}"; do
        # Handle glob patterns
        for file in $location; do
            [[ ! -f "$file" ]] && continue
            
            log_info "  Checking $file..."
            while IFS= read -r line; do
                TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
                [[ "$line" =~ ^#.*$ ]] && continue
                [[ -z "$line" ]] && continue
                
                for pattern in "${MALICIOUS_PATTERNS[@]}"; do
                    if echo "$line" | grep -qiE "$pattern"; then
                        log_error "SUSPICIOUS in $file: $line"
                        SUSPICIOUS_FOUND=$((SUSPICIOUS_FOUND + 1))
                    fi
                done
            done < "$file"
        done
    done
}

###############################################################################
# Check for LD_PRELOAD Persistence
###############################################################################
check_ld_preload() {
    log_info "Checking for LD_PRELOAD persistence..."
    
    local ld_preload_locations=(
        "/etc/ld.so.preload"
        "/etc/ld.so.conf.d"
    )
    
    for location in "${ld_preload_locations[@]}"; do
        [[ ! -e "$location" ]] && continue
        
        if [[ -f "$location" ]]; then
            log_warn "Found $location - checking content"
            while IFS= read -r line; do
                TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
                [[ "$line" =~ ^#.*$ ]] && continue
                [[ -z "$line" ]] && continue
                
                # Any .so file in ld.so.preload could be suspicious
                if [[ "$line" == *.so* ]]; then
                    log_error "POTENTIAL PERSISTENCE: $location contains: $line"
                    SUSPICIOUS_FOUND=$((SUSPICIOUS_FOUND + 1))
                fi
            done < "$location"
        fi
    done
}

###############################################################################
# Check SSH Persistence
###############################################################################
check_ssh_persistence() {
    log_info "Checking SSH configurations for persistence..."
    
    local ssh_configs=(
        "/etc/ssh/sshd_config"
        "/home/*/.ssh/authorized_keys"
        "/root/.ssh/authorized_keys"
    )
    
    for config in "${ssh_configs[@]}"; do
        for file in $config; do
            [[ ! -f "$file" ]] && continue
            
            log_info "  Checking $file..."
            while IFS= read -r line; do
                TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
                [[ "$line" =~ ^#.*$ ]] && continue
                [[ -z "$line" ]] && continue
                
                # Check for suspicious SSH options
                if echo "$line" | grep -qiE "command=|no-pty|no-port-forwarding|restrict"; then
                    log_warn "SSH forced command detected in $file"
                    log_warn "  $line"
                fi
            done < "$file"
        done
    done
}

###############################################################################
# Check for Suspicious Processes Running at Boot
###############################################################################
check_boot_persistence() {
    log_info "Checking for boot persistence mechanisms..."
    
    # Check systemd-run entries
    local user_services=$(find /etc/systemd/user.d /etc/systemd/system.d -name "*.conf" 2>/dev/null || true)
    
    for conf in $user_services; do
        [[ ! -f "$conf" ]] && continue
        
        log_info "  Checking $conf..."
        while IFS= read -r line; do
            TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
            [[ "$line" =~ ^#.*$ ]] && continue
            [[ -z "$line" ]] && continue
            
            for pattern in "${MALICIOUS_PATTERNS[@]}"; do
                if echo "$line" | grep -qiE "$pattern"; then
                    log_error "SUSPICIOUS in systemd config $conf: $line"
                    SUSPICIOUS_FOUND=$((SUSPICIOUS_FOUND + 1))
                fi
            done
        done < "$conf"
    done
}

###############################################################################
# Check for Kernel Module Persistence
###############################################################################
check_kernel_modules() {
    log_info "Checking for suspicious kernel modules..."
    
    if [[ ! -f /proc/modules ]]; then
        log_warn "Cannot access /proc/modules; skipping kernel module check"
        return
    fi
    
    # List all loaded modules
    while IFS= read -r module_line; do
        TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
        module_name=$(echo "$module_line" | awk '{print $1}')
        
        # Flag suspicious module names
        if echo "$module_name" | grep -qiE "rootkit|backdoor|payload|exploit|shadow|diamorphine|lizard"; then
            log_error "SUSPICIOUS kernel module loaded: $module_name"
            SUSPICIOUS_FOUND=$((SUSPICIOUS_FOUND + 1))
        fi
    done < /proc/modules
}

###############################################################################
# Generate Report
###############################################################################
generate_report() {
    echo ""
    echo "=========================================="
    echo "Persistence Detection Report"
    if [[ "$UBUNTU_24_VERIFIED" == "true" ]]; then
        echo "Ubuntu Server 24 LTS"
    fi
    echo "=========================================="
    echo ""
    echo "Total items checked: $TOTAL_CHECKED"
    echo "Suspicious items found: $SUSPICIOUS_FOUND"
    echo ""
    
    if [[ $SUSPICIOUS_FOUND -eq 0 ]]; then
        log_success "No obvious malicious persistence detected!"
    else
        log_error "ALERT: $SUSPICIOUS_FOUND suspicious items detected!"
        log_warn "Please review the items marked above carefully"
        log_warn "False positives are possible - verify each finding manually"
    fi
    
    echo ""
    echo "Next steps if threats found:"
    echo "1. Review suspicious cron entries with: crontab -l (for current user)"
    echo "2. Check system logs: journalctl -xe"
    echo "3. Use 'ps aux' to see running processes"
    echo "4. Check network connections: netstat -tlnp or ss -tlnp"
    echo "5. Consider running rootkit detection: aide, rkhunter, or chkrootkit"
    echo "=========================================="
}

###############################################################################
# Main Execution
###############################################################################
main() {
    echo ""
    echo "=========================================="
    echo "Malicious Crontab & Persistence Scanner"
    echo "Ubuntu Server 24 LTS Edition"
    echo "=========================================="
    echo ""
    
    # Verify Ubuntu 24 LTS
    if ! verify_ubuntu_24; then
        log_error "OS verification failed - exiting"
        exit 1
    fi
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_warn "This script should be run as root for full coverage"
        log_warn "Some checks may be skipped"
    fi
    
    # Run all checks
    check_system_crontabs
    check_user_crontabs
    check_at_jobs
    check_systemd_timers
    check_startup_scripts
    check_ld_preload
    check_ssh_persistence
    check_boot_persistence
    check_kernel_modules
    
    # Generate report
    generate_report
}

# Execute main
main "$@"
