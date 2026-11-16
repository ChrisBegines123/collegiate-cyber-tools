#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

WEB_DIRS=(
    "/var/www/html"
    "/var/www/html/upload"
    "/var/www/opencart"
)

PROGRESS_EVERY=200

PHP_SHELL_PATTERNS=(
    "eval.*base64_decode"
    "eval.*gzinflate"
    "eval.*str_rot13"
    "system.*\\\$_(GET|POST|REQUEST)"
    "exec.*\\\$_(GET|POST|REQUEST)"
    "shell_exec.*\\\$_"
    "passthru.*\\\$_"
    "popen.*\\\$_"
    "proc_open"
    "assert.*\\\$_"
    "file_get_contents.*php://input"
    "fsockopen"
    "socket_create"
    "preg_replace.*\/e"
    "create_function.*\\\$_"
    "call_user_func.*\\\$_"
    "array_map.*assert"
    "move_uploaded_file.*\.php"
)

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
    "alfa.php"
)

FILES_SCANNED=0
SUSPECT_FILES=0
SUSPECT_DETAILS=()

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
ok() { echo -e "${GREEN}[OK]${NC} $*"; }
bad() { echo -e "${RED}[ALERT]${NC} $*"; }

show_usage() {
    cat << EOF
PHP Webshell Checker

Usage:
  $0
  $0 /custom/web/root /another/path

If no paths are provided, default web directories are scanned.
For OpenCart, you can run: $0 /var/www/html
EOF
}

scan_php_file() {
    local file="$1"
    local flagged=0
    local file_name
    local matches=()
    file_name="$(basename "$file")"

    for shell_name in "${KNOWN_SHELL_NAMES[@]}"; do
        if [[ "$file_name" == "$shell_name" ]]; then
            bad "Known shell filename: $file"
            matches+=("known-name:$shell_name")
            flagged=1
            break
        fi
    done

    for pattern in "${PHP_SHELL_PATTERNS[@]}"; do
        if grep -qiE "$pattern" "$file" 2>/dev/null; then
            bad "Pattern match in $file -> $pattern"
            matches+=("pattern:$pattern")
            flagged=1
        fi
    done

    if [[ "$flagged" -eq 1 ]]; then
        ((SUSPECT_FILES+=1))
        SUSPECT_DETAILS+=("$file | ${matches[*]}")
    fi
}

scan_directory() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0

    info "Scanning: $dir"
    while IFS= read -r -d '' php_file; do
        if echo "$php_file" | grep -qE "backup|\.bak|\.old|\.backup|/\.|node_modules|vendor/phpunit|/image/cache/|/storage/cache/|/system/storage/cache/|/logs/"; then
            continue
        fi
        ((FILES_SCANNED+=1))
        if (( FILES_SCANNED % PROGRESS_EVERY == 0 )); then
            info "Progress: $FILES_SCANNED PHP files scanned..."
        fi
        scan_php_file "$php_file"
    done < <(find "$dir" -type f -name "*.php" -print0 2>/dev/null || true)
}

main() {
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        show_usage
        exit 0
    fi

    info "Starting PHP webshell check"

    if [[ "$#" -gt 0 ]]; then
        for dir in "$@"; do
            scan_directory "$dir"
        done
    else
        for pattern_dir in "${WEB_DIRS[@]}"; do
            for dir in $pattern_dir; do
                scan_directory "$dir"
            done
        done
    fi

    info "Files scanned: $FILES_SCANNED"
    info "Suspicious files: $SUSPECT_FILES"

    if [[ "$SUSPECT_FILES" -gt 0 ]]; then
        echo ""
        bad "Suspicious file details:"
        for item in "${SUSPECT_DETAILS[@]}"; do
            bad " - $item"
        done
        bad "Potential webshell indicators found"
        exit 1
    fi

    ok "No obvious webshell indicators found"
}

main "$@"
