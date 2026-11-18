#!/bin/bash

# Proper error handling
set -uo pipefail

###############################################################################
# PHP Webshell & File Integrity Scanner - Ubuntu Server 24 LTS
# Detects PHP shells, monitors file changes, and maintains file integrity
# Optimized for: E-commerce servers running Ubuntu Server 24 LTS
# Features: PHP shell detection, continuous monitoring, hash-based integrity
###############################################################################

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCAN_INTERVAL=180  # Scan every 3 minutes (180 seconds)
HASH_DB="/var/tmp/.filehash_db.txt"
SCAN_LOG="/var/log/webshell_scanner.log"
ALERT_LOG="/var/log/webshell_alerts.log"

# Web directories to monitor (common e-commerce paths)
WEB_DIRS=(
    "/var/www"
    "/var/www/html"
    "/usr/share/nginx/html"
    "/opt/magento"
    "/opt/wordpress"
    "/var/www/wordpress"
    "/var/www/woocommerce"
    "/home/*/public_html"
)

# Counters
SHELLS_FOUND=0
FILES_CHANGED=0
NEW_FILES=0
TOTAL_SCANNED=0

# Initialize log files
initialize_logs() {
    # Try to create log files, fallback to /tmp if /var/log is not writable
    if ! touch "$SCAN_LOG" 2>/dev/null; then
        SCAN_LOG="/tmp/webshell_scanner.log"
        touch "$SCAN_LOG" 2>/dev/null || true
    fi
    
    if ! touch "$ALERT_LOG" 2>/dev/null; then
        ALERT_LOG="/tmp/webshell_alerts.log"
        touch "$ALERT_LOG" 2>/dev/null || true
    fi
}

# Helper functions
log_info() { 
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} [INFO] $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" >> "$SCAN_LOG" 2>/dev/null || true
}

log_warn() { 
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} [WARN] $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" >> "$SCAN_LOG" 2>/dev/null || true
}

log_success() { 
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} [SUCCESS] $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $*" >> "$SCAN_LOG" 2>/dev/null || true
}

log_error() { 
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} [ERROR] $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >> "$SCAN_LOG" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >> "$ALERT_LOG" 2>/dev/null || true
}

log_critical() {
    echo -e "${MAGENTA}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} [CRITICAL] $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CRITICAL] $*" >> "$SCAN_LOG" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CRITICAL] $*" >> "$ALERT_LOG" 2>/dev/null || true
}

# PHP Webshell signatures and patterns
PHP_SHELL_PATTERNS=(
    "eval.*base64_decode"           # Encoded payload execution
    "eval.*gzinflate"                # Compressed payload
    "eval.*str_rot13"                # ROT13 obfuscation
    "system.*\\\$_GET"               # System command execution via GET
    "system.*\\\$_POST"              # System command execution via POST
    "exec.*\\\$_GET"                 # Exec with user input
    "exec.*\\\$_POST"                # Exec via POST
    "shell_exec.*\\\$_"              # Shell execution
    "passthru.*\\\$_"                # Passthru execution
    "popen.*\\\$_"                   # Process open
    "proc_open"                      # Process manipulation
    "pcntl_exec"                     # Process control execution
    "assert.*\\\$_"                  # Assert execution
    "\`.*\\\$_"                      # Backtick execution
    "file_get_contents.*php://input" # Direct input reading
    "fsockopen"                      # Network socket (reverse shell)
    "socket_create"                  # Socket creation
    "curl_exec.*shell"               # Curl-based execution
    "preg_replace.*\/e"              # Regex execution (deprecated but dangerous)
    "create_function.*\\\$_"         # Dynamic function creation
    "ReflectionFunction"             # Reflection-based execution
    "call_user_func.*\\\$_"          # Dynamic function calls
    "call_user_func_array"           # Array-based function calls
    "array_map.*assert"              # Array map with assert
    "file_put_contents.*\\\$_"       # File writing from user input
    "fwrite.*\\\$_POST"              # Direct file write
    "mb_ereg_replace.*e"             # Multibyte regex execution
    "move_uploaded_file.*\.php"      # Suspicious file upload
)

# Known webshell filenames (common across the wild)
KNOWN_SHELL_NAMES=(
    "c99.php"
    "r57.php"
    "b374k.php"
    "wso.php"
    "shell.php"
    "cmd.php"
    "backdoor.php"
    "webshell.php"
    "php-backdoor.php"
    "bypass.php"
    "alfa.php"
    "indoxploit.php"
    "adminer.php"
    "mysql.php"
    "dump.php"
    "error_log.php"
)

###############################################################################
# Verify Ubuntu 24 LTS
###############################################################################
verify_ubuntu_24() {
    if [[ -f /etc/os-release ]]; then
        if grep -qE "VERSION_CODENAME=noble|VERSION_ID=\"24\.04\"" /etc/os-release; then
            log_success "Ubuntu Server 24 LTS (Noble Numbat) detected"
            return 0
        else
            log_warn "Not Ubuntu Server 24 LTS - proceeding with caution"
        fi
    fi
    return 0
}

###############################################################################
# Initialize hash database
###############################################################################
initialize_hash_db() {
    if [[ ! -f "$HASH_DB" ]]; then
        log_info "Initializing file integrity database..."
        touch "$HASH_DB" 2>/dev/null || {
            log_error "Cannot create hash database at $HASH_DB"
            HASH_DB="/tmp/.filehash_db_$$.txt"
            log_warn "Using temporary database: $HASH_DB"
            touch "$HASH_DB" 2>/dev/null || return 1
        }
        chmod 600 "$HASH_DB" 2>/dev/null || true
        log_success "Hash database created at $HASH_DB"
    else
        log_info "Using existing hash database: $HASH_DB"
        # Validate database is writable
        if ! touch "$HASH_DB" 2>/dev/null; then
            log_error "Hash database is not writable: $HASH_DB"
            return 1
        fi
    fi
    return 0
}

###############################################################################
# Calculate file hash
###############################################################################
calculate_hash() {
    local file="$1"
    if [[ -f "$file" && -r "$file" ]]; then
        sha256sum "$file" 2>/dev/null | awk '{print $1}' || echo ""
    else
        echo ""
    fi
}

###############################################################################
# Update file hash in database
###############################################################################
update_hash() {
    local file="$1"
    local hash="$2"
    
    # Skip if hash is empty
    [[ -z "$hash" ]] && return 0
    
    # Create temp file for safe update
    local temp_db="${HASH_DB}.tmp.$$"
    
    # Remove old entry if exists, create new database
    if [[ -f "$HASH_DB" ]]; then
        grep -v -F "${file}|" "$HASH_DB" 2>/dev/null > "$temp_db" || touch "$temp_db"
    else
        touch "$temp_db"
    fi
    
    # Add new entry
    echo "${file}|${hash}|$(date +%s)" >> "$temp_db"
    
    # Replace old database
    mv "$temp_db" "$HASH_DB" 2>/dev/null || true
    chmod 600 "$HASH_DB" 2>/dev/null || true
    
    return 0
}

###############################################################################
# Get stored hash for file
###############################################################################
get_stored_hash() {
    local file="$1"
    
    if [[ ! -f "$HASH_DB" ]]; then
        echo ""
        return 0
    fi
    
    # Use grep with -F for literal string match (no regex)
    local result=$(grep -F "${file}|" "$HASH_DB" 2>/dev/null | head -1 | cut -d'|' -f2 || echo "")
    echo "$result"
    return 0
}

###############################################################################
# Scan file for PHP webshell patterns
###############################################################################
scan_php_file() {
    local file="$1"
    local suspicious=0
    local patterns_found=()
    
    # Check filename against known shells
    local basename=$(basename "$file" 2>/dev/null || echo "unknown")
    for shell_name in "${KNOWN_SHELL_NAMES[@]}"; do
        if [[ "$basename" == "$shell_name" ]]; then
            log_critical "KNOWN WEBSHELL FILENAME: $file"
            SHELLS_FOUND=$((SHELLS_FOUND + 1))
            suspicious=1
        fi
    done
    
    # Check file content for malicious patterns
    if [[ -f "$file" && -r "$file" ]]; then
        for pattern in "${PHP_SHELL_PATTERNS[@]}"; do
            if grep -qiE "$pattern" "$file" 2>/dev/null; then
                patterns_found+=("$pattern")
                suspicious=1
            fi
        done
        
        # Additional checks for obfuscated code
        # Check for high entropy (indicator of encoding)
        local entropy=$(cat "$file" 2>/dev/null | tr -cd '[:alnum:]' | fold -w1 | sort | uniq -c | awk '{print $1}' | sort -nr | head -1 || echo "0")
        if [[ $entropy -gt 1000 ]]; then
            # Highly repetitive characters - possible encoding
            if grep -qE "eval|base64|gzinflate|str_rot13" "$file" 2>/dev/null; then
                patterns_found+=("high-entropy-with-eval")
                suspicious=1
            fi
        fi
        
        # Check for single-line PHP files (common in shells)
        local line_count=$(wc -l < "$file" 2>/dev/null || echo "0")
        if [[ $line_count -eq 1 ]] && grep -qE "eval|system|exec|shell_exec|passthru" "$file" 2>/dev/null; then
            patterns_found+=("single-line-execution")
            suspicious=1
        fi
        
        # Report findings
        if [[ $suspicious -eq 1 ]]; then
            log_critical "SUSPICIOUS PHP FILE: $file"
            for found_pattern in "${patterns_found[@]}"; do
                log_error "  → Pattern matched: $found_pattern"
            done
            SHELLS_FOUND=$((SHELLS_FOUND + 1))
        fi
    fi
    
    return 0
}

###############################################################################
# Check file integrity
###############################################################################
check_file_integrity() {
    local file="$1"
    local current_hash=$(calculate_hash "$file")
    local stored_hash=$(get_stored_hash "$file")
    
    if [[ -z "$stored_hash" ]]; then
        # New file - add to database
        if [[ -n "$current_hash" ]]; then
            update_hash "$file" "$current_hash"
        fi
        log_warn "NEW FILE DETECTED: $file"
        NEW_FILES=$((NEW_FILES + 1))
        return 1  # Indicate new file
    elif [[ "$current_hash" != "$stored_hash" ]]; then
        # File modified
        log_error "FILE MODIFIED: $file"
        log_error "  Old hash: $stored_hash"
        log_error "  New hash: $current_hash"
        if [[ -n "$current_hash" ]]; then
            update_hash "$file" "$current_hash"
        fi
        FILES_CHANGED=$((FILES_CHANGED + 1))
        return 2  # Indicate modification
    fi
    
    return 0  # File unchanged
}

###############################################################################
# Scan web directory
###############################################################################
scan_web_directory() {
    local dir="$1"
    local file_count=0
    
    if [[ ! -d "$dir" ]]; then
        log_warn "Directory does not exist: $dir"
        return 0
    fi
    
    if [[ ! -r "$dir" ]]; then
        log_error "Directory not readable: $dir"
        return 0
    fi
    
    log_info "Scanning directory: $dir"
    
    # Temporarily disable pipefail for the find loops
    set +o pipefail
    
    # Find all PHP files (exclude backup directories common patterns)
    while IFS= read -r -d '' php_file; do
        # Skip backup directories and common non-web paths
        if echo "$php_file" | grep -qE "backup|\.bak|\.old|\.backup|/\.|node_modules|vendor/phpunit" 2>/dev/null; then
            continue
        fi
        
        TOTAL_SCANNED=$((TOTAL_SCANNED + 1))
        file_count=$((file_count + 1))
        
        # Scan for webshells (don't exit on failure)
        scan_php_file "$php_file" || true
        
        # Check integrity (don't exit on failure)
        check_file_integrity "$php_file" || true
        
    done < <(find "$dir" -type f -name "*.php" -print0 2>/dev/null || true)
    
    # Also check for suspicious uploaded files
    while IFS= read -r -d '' suspect_file; do
        if echo "$suspect_file" | grep -qE "backup|\.bak|\.old|\.backup|/\." 2>/dev/null; then
            continue
        fi
        
        TOTAL_SCANNED=$((TOTAL_SCANNED + 1))
        file_count=$((file_count + 1))
        
        # Check if it's actually PHP despite extension
        if file "$suspect_file" 2>/dev/null | grep -qE "PHP|ASCII.*script"; then
            log_warn "SUSPICIOUS: PHP-like file with wrong extension: $suspect_file"
            scan_php_file "$suspect_file" || true
            check_file_integrity "$suspect_file" || true
        fi
    done < <(find "$dir" -type f \( -name "*.suspected" -o -name "*.txt.php" -o -name "*.jpg.php" -o -name "*.png.php" \) -print0 2>/dev/null || true)
    
    # Re-enable pipefail
    set -o pipefail
    
    log_info "  → Scanned $file_count files in $dir"
    return 0
}

###############################################################################
# Single scan iteration
###############################################################################
run_single_scan() {
    # Reset counters
    SHELLS_FOUND=0
    FILES_CHANGED=0
    NEW_FILES=0
    TOTAL_SCANNED=0
    
    log_info "═══════════════════════════════════════════════════════════"
    log_info "Starting PHP webshell & integrity scan"
    log_info "═══════════════════════════════════════════════════════════"
    
    # Scan each web directory
    for web_dir in "${WEB_DIRS[@]}"; do
        # Handle glob patterns - disable pipefail temporarily for glob expansion
        set +o pipefail
        shopt -s nullglob 2>/dev/null || true
        local expanded_dirs=($web_dir)
        shopt -u nullglob 2>/dev/null || true
        set -o pipefail
        
        # If no matches, try the literal path
        if [[ ${#expanded_dirs[@]} -eq 0 ]]; then
            expanded_dirs=("$web_dir")
        fi
        
        for dir in "${expanded_dirs[@]}"; do
            if [[ -d "$dir" ]]; then
                log_info "Checking directory: $dir"
                scan_web_directory "$dir" || {
                    log_warn "Failed to fully scan $dir - continuing with next directory"
                    continue
                }
            else
                log_info "Skipping non-existent directory: $dir"
            fi
        done
    done
    
    # Generate scan report
    log_info "───────────────────────────────────────────────────────────"
    log_info "Scan completed"
    log_info "  Files scanned: $TOTAL_SCANNED"
    log_info "  Webshells found: $SHELLS_FOUND"
    log_info "  Modified files: $FILES_CHANGED"
    log_info "  New files: $NEW_FILES"
    
    if [[ $SHELLS_FOUND -gt 0 ]]; then
        log_critical "⚠️  ALERT: $SHELLS_FOUND potential webshells detected!"
        log_critical "⚠️  Check $ALERT_LOG for details"
    fi
    
    if [[ $FILES_CHANGED -gt 0 ]]; then
        log_error "⚠️  WARNING: $FILES_CHANGED files were modified"
    fi
    
    if [[ $NEW_FILES -gt 0 ]]; then
        log_warn "ℹ️  INFO: $NEW_FILES new files detected"
    fi
    
    if [[ $SHELLS_FOUND -eq 0 && $FILES_CHANGED -eq 0 && $NEW_FILES -eq 0 ]]; then
        log_success "✓ No threats or changes detected"
    fi
    
    log_info "═══════════════════════════════════════════════════════════"
}

###############################################################################
# Continuous monitoring mode
###############################################################################
continuous_monitor() {
    log_info "Starting continuous monitoring mode"
    log_info "Scan interval: $SCAN_INTERVAL seconds"
    log_info "Press Ctrl+C to stop"
    echo ""
    
    # Trap Ctrl+C for clean exit
    trap 'log_info "Monitoring stopped by user"; exit 0' INT TERM
    
    while true; do
        run_single_scan
        
        log_info "Next scan in $SCAN_INTERVAL seconds..."
        echo ""
        sleep "$SCAN_INTERVAL"
    done
}

###############################################################################
# Check for uploaded shells in temp directories
###############################################################################
check_temp_uploads() {
    log_info "Checking temporary upload directories..."
    
    local temp_dirs=(
        "/tmp"
        "/var/tmp"
        "/dev/shm"
        "/var/www/*/uploads"
        "/var/www/*/tmp"
    )
    
    for temp_dir in "${temp_dirs[@]}"; do
        for dir in $temp_dir; do
            if [[ -d "$dir" ]]; then
                # Look for recently created PHP files
                find "$dir" -type f -name "*.php" -mtime -1 -print0 2>/dev/null | while IFS= read -r -d '' php_file; do
                    log_warn "Recent PHP file in temp location: $php_file"
                    scan_php_file "$php_file" || true
                done
            fi
        done
    done
    
    return 0
}

###############################################################################
# Quick scan mode (single pass)
###############################################################################
quick_scan() {
    log_info "Running quick scan (single pass)..."
    initialize_hash_db
    run_single_scan
    check_temp_uploads
    
    echo ""
    log_info "Quick scan complete. Review logs at:"
    log_info "  Scan log: $SCAN_LOG"
    log_info "  Alert log: $ALERT_LOG"
}

###############################################################################
# Initialize baseline (first run)
###############################################################################
initialize_baseline() {
    log_info "Initializing baseline - establishing file hashes..."
    log_warn "This may take a while depending on the number of files..."
    
    initialize_hash_db || {
        log_error "Failed to initialize hash database"
        return 1
    }
    
    # First pass - just record hashes without alerting
    local baseline_count=0
    local temp_count_file="/tmp/baseline_count_$$"
    echo "0" > "$temp_count_file"
    
    for web_dir in "${WEB_DIRS[@]}"; do
        # Handle glob patterns
        set +o pipefail
        shopt -s nullglob 2>/dev/null || true
        local expanded_dirs=($web_dir)
        shopt -u nullglob 2>/dev/null || true
        set -o pipefail
        
        # If no matches, try the literal path
        if [[ ${#expanded_dirs[@]} -eq 0 ]]; then
            expanded_dirs=("$web_dir")
        fi
        
        for dir in "${expanded_dirs[@]}"; do
            if [[ -d "$dir" ]]; then
                log_info "Processing: $dir"
                
                # Disable pipefail for find operation
                set +o pipefail
                while IFS= read -r -d '' php_file; do
                    if echo "$php_file" | grep -qE "backup|\.bak|\.old|\.backup|/\." 2>/dev/null; then
                        continue
                    fi
                    local hash=$(calculate_hash "$php_file")
                    if [[ -n "$hash" ]]; then
                        update_hash "$php_file" "$hash" || true
                        local count=$(cat "$temp_count_file" 2>/dev/null || echo "0")
                        echo $((count + 1)) > "$temp_count_file"
                    fi
                done < <(find "$dir" -type f -name "*.php" -print0 2>/dev/null || true)
                set -o pipefail
            else
                log_info "Skipping non-existent: $dir"
            fi
        done
    done
    
    baseline_count=$(cat "$temp_count_file" 2>/dev/null || echo "0")
    rm -f "$temp_count_file"
    
    log_success "Baseline established for $baseline_count files"
    log_info "Hash database: $HASH_DB"
    log_info "You can now run continuous monitoring with: $0 --monitor"
    return 0
}

###############################################################################
# Show usage
###############################################################################
show_usage() {
    cat << EOF
PHP Webshell Scanner & File Integrity Monitor
Ubuntu Server 24 LTS Edition

Usage: $0 [OPTIONS]

OPTIONS:
    --quick, -q          Run a single scan and exit
    --monitor, -m        Run continuous monitoring (scans every $SCAN_INTERVAL seconds)
    --baseline, -b       Initialize baseline file hashes (first-time setup)
    --interval <secs>    Set scan interval for monitoring mode (default: $SCAN_INTERVAL)
    --help, -h           Show this help message

EXAMPLES:
    $0 --baseline        # First run - establish baseline
    $0 --quick           # Run single scan
    $0 --monitor         # Start continuous monitoring
    $0 --monitor --interval 300  # Monitor with 5-minute intervals

LOGS:
    Scan log:   $SCAN_LOG
    Alert log:  $ALERT_LOG
    Hash DB:    $HASH_DB

EOF
}

###############################################################################
# Main Execution
###############################################################################
main() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  PHP Webshell Scanner & File Integrity Monitor"
    echo "  Ubuntu Server 24 LTS - E-commerce Security"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    
    # Initialize logging
    initialize_logs
    
    # Verify Ubuntu 24
    verify_ubuntu_24
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        log_error "Use: sudo $0"
        exit 1
    fi
    
    # Parse arguments
    local mode="help"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --quick|-q)
                mode="quick"
                shift
                ;;
            --monitor|-m)
                mode="monitor"
                shift
                ;;
            --baseline|-b)
                mode="baseline"
                shift
                ;;
            --interval)
                SCAN_INTERVAL="$2"
                shift 2
                ;;
            --help|-h)
                mode="help"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Execute based on mode
    case $mode in
        quick)
            quick_scan
            ;;
        monitor)
            initialize_hash_db
            continuous_monitor
            ;;
        baseline)
            initialize_baseline
            ;;
        help)
            show_usage
            ;;
        *)
            log_error "Invalid mode"
            show_usage
            exit 1
            ;;
    esac
}

# Execute main
main "$@"
