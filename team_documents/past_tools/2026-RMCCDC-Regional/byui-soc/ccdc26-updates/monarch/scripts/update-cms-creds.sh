#!/bin/bash
# CCDC26 Monarch - CMS Database Credential Updater
# Updates DB passwords in web application config files after password rotation
# Usage: update-cms-creds.sh NEW_DB_PASSWORD [DB_USER]
#
# Searches common web roots for CMS config files and updates the DB password.
# Restarts web server after changes.

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then error "Must be run as root"; exit 1; fi
if [ $# -lt 1 ]; then error "Usage: $0 NEW_DB_PASSWORD [DB_USER]"; exit 1; fi

NEW_PASS="$1"
DB_USER="${2:-}"
SEARCH_DIRS="/var/www /srv /opt /home"
CHANGED=0

backup_file() {
    cp "$1" "${1}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null
}

update_wordpress() {
    local f="$1"
    info "WordPress: $f"
    backup_file "$f"
    sed -i "s/\(define(\s*'DB_PASSWORD'\s*,\s*'\)[^']*'/\1${NEW_PASS}'/" "$f"
    ok "  Updated DB_PASSWORD"
    CHANGED=$((CHANGED + 1))
}

update_opencart() {
    local f="$1"
    info "OpenCart: $f"
    backup_file "$f"
    sed -i "s/\(define(\s*'DB_PASSWORD'\s*,\s*'\)[^']*'/\1${NEW_PASS}'/" "$f"
    ok "  Updated DB_PASSWORD"
    CHANGED=$((CHANGED + 1))
}

update_joomla() {
    local f="$1"
    info "Joomla: $f"
    backup_file "$f"
    sed -i "s/\(public \$password\s*=\s*'\)[^']*'/\1${NEW_PASS}'/" "$f"
    ok "  Updated \$password"
    CHANGED=$((CHANGED + 1))
}

update_prestashop() {
    local f="$1"
    info "PrestaShop: $f"
    backup_file "$f"
    if [[ "$f" == *.yml ]]; then
        sed -i "s/\(database_password:\s*\).*/\1${NEW_PASS}/" "$f"
    else
        sed -i "s/\('database_password'\s*=>\s*'\)[^']*'/\1${NEW_PASS}'/" "$f"
    fi
    ok "  Updated database_password"
    CHANGED=$((CHANGED + 1))
}

update_env() {
    local f="$1"
    info "Env file: $f"
    backup_file "$f"
    sed -i "s/^\(DB_PASSWORD=\).*/\1${NEW_PASS}/" "$f"
    if [ -n "$DB_USER" ]; then
        sed -i "s/^\(DB_USERNAME=\).*/\1${DB_USER}/" "$f"
    fi
    ok "  Updated DB_PASSWORD"
    CHANGED=$((CHANGED + 1))
}

info "Searching for CMS config files..."

for dir in $SEARCH_DIRS; do
    [ -d "$dir" ] || continue

    while IFS= read -r f; do
        grep -ql "DB_PASSWORD" "$f" 2>/dev/null && update_wordpress "$f"
    done < <(find "$dir" -maxdepth 6 -name "wp-config.php" -type f 2>/dev/null)

    while IFS= read -r f; do
        [[ "$f" == *wp-config.php ]] && continue
        grep -ql "DB_PASSWORD" "$f" 2>/dev/null && update_opencart "$f"
    done < <(find "$dir" -maxdepth 6 -name "config.php" -type f 2>/dev/null)

    while IFS= read -r f; do
        grep -ql '$password' "$f" 2>/dev/null && update_joomla "$f"
    done < <(find "$dir" -maxdepth 6 -name "configuration.php" -type f 2>/dev/null)

    while IFS= read -r f; do
        grep -ql "database_password" "$f" 2>/dev/null && update_prestashop "$f"
    done < <(find "$dir" -maxdepth 6 \( -name "parameters.php" -o -name "parameters.yml" \) -type f 2>/dev/null)

    while IFS= read -r f; do
        grep -ql "^DB_PASSWORD=" "$f" 2>/dev/null && update_env "$f"
    done < <(find "$dir" -maxdepth 6 -name ".env" -type f 2>/dev/null)
done

if [ "$CHANGED" -eq 0 ]; then
    warn "No CMS config files found to update"
    exit 0
fi

ok "Updated $CHANGED config file(s)"

info "Restarting web server..."
if systemctl is-active --quiet apache2 2>/dev/null; then systemctl restart apache2 && ok "Restarted apache2"
elif systemctl is-active --quiet httpd 2>/dev/null; then systemctl restart httpd && ok "Restarted httpd"
fi
if systemctl is-active --quiet nginx 2>/dev/null; then systemctl restart nginx && ok "Restarted nginx"; fi
if systemctl is-active --quiet php-fpm 2>/dev/null; then systemctl restart php-fpm && ok "Restarted php-fpm"
elif systemctl is-active --quiet php8.1-fpm 2>/dev/null; then systemctl restart php8.1-fpm && ok "Restarted php8.1-fpm"
elif systemctl is-active --quiet php8.2-fpm 2>/dev/null; then systemctl restart php8.2-fpm && ok "Restarted php8.2-fpm"
fi

ok "CMS credential update complete"
