#!/bin/bash
#=============================================================================
# Fix OpenCart Connection and Stylesheet Errors
#=============================================================================
# Fixes common issues:
# - Stylesheet not loading (NS_ERROR_CONNECTION)
# - Admin panel connection refused
# - Missing Apache modules
# - Incorrect file permissions
# - .htaccess issues
#
# Usage:
#   sudo ./fix-opencart-errors.sh
#=============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }

# Must be root
if [ "$EUID" -ne 0 ]; then
   error "Must run as root"
   exit 1
fi

WEBROOT="/var/www/html"

echo ""
echo "=================================================="
echo "  OpenCart Error Troubleshooting"
echo "=================================================="
echo ""

# 1. Check Apache is running
info "[1/10] Checking Apache status..."
if systemctl is-active --quiet apache2; then
    success "Apache is running"
else
    error "Apache is NOT running!"
    echo "  Starting Apache..."
    systemctl start apache2
    if systemctl is-active --quiet apache2; then
        success "Apache started"
    else
        error "Failed to start Apache"
        echo "  Check logs: journalctl -xeu apache2"
        exit 1
    fi
fi
echo ""

# 2. Check Apache configuration
info "[2/10] Testing Apache configuration..."
if apache2ctl configtest 2>&1 | grep -q "Syntax OK"; then
    success "Apache config is valid"
else
    error "Apache config has errors!"
    apache2ctl configtest
    exit 1
fi
echo ""

# 3. Check if port 80 is listening
info "[3/10] Checking if Apache is listening on port 80..."
if netstat -tuln | grep -q ":80 "; then
    success "Apache listening on port 80"
else
    error "Apache NOT listening on port 80!"
    echo "  Something else may be using the port"
    echo "  Check with: sudo lsof -i :80"
fi
echo ""

# 4. Enable required Apache modules
info "[4/10] Enabling required Apache modules..."
MODULES_NEEDED="rewrite headers ssl"
for mod in $MODULES_NEEDED; do
    if a2query -m $mod &>/dev/null; then
        echo "  - $mod: already enabled"
    else
        echo "  - $mod: enabling..."
        a2enmod $mod &>/dev/null
    fi
done
success "All required modules enabled"
echo ""

# 5. Check OpenCart directory exists
info "[5/10] Checking OpenCart installation..."
if [ ! -d "$WEBROOT" ]; then
    error "Web root not found: $WEBROOT"
    exit 1
fi

if [ ! -f "$WEBROOT/config.php" ]; then
    error "OpenCart config.php not found!"
    echo "  Expected: $WEBROOT/config.php"
    exit 1
fi

success "OpenCart files found"
echo ""

# 6. Check and fix file permissions
info "[6/10] Fixing file permissions..."

# Web server user (www-data on Ubuntu)
WEB_USER="www-data"

# Set ownership
chown -R $WEB_USER:$WEB_USER "$WEBROOT" 2>/dev/null || true

# Directories: 755
find "$WEBROOT" -type d -exec chmod 755 {} \; 2>/dev/null || true

# Files: 644
find "$WEBROOT" -type f -exec chmod 644 {} \; 2>/dev/null || true

# Config files should be readable
chmod 644 "$WEBROOT/config.php" 2>/dev/null || true
[ -f "$WEBROOT/admin/config.php" ] && chmod 644 "$WEBROOT/admin/config.php"

# Image and cache directories need to be writable
chmod -R 777 "$WEBROOT/image/" 2>/dev/null || true
chmod -R 777 "$WEBROOT/system/storage/" 2>/dev/null || true
chmod -R 777 "$WEBROOT/system/cache/" 2>/dev/null || true

success "Permissions fixed"
echo ""

# 7. Check .htaccess files
info "[7/10] Checking .htaccess configuration..."

if [ -f "$WEBROOT/.htaccess" ]; then
    echo "  .htaccess found in web root"
    
    # Check if it allows overrides
    if grep -q "AllowOverride" /etc/apache2/sites-available/000-default.conf 2>/dev/null; then
        echo "  AllowOverride already configured"
    else
        warn "  AllowOverride may not be set in Apache config"
        echo "  Adding AllowOverride All to Apache config..."
        
        # Add AllowOverride to default site config
        if ! grep -q "<Directory /var/www/html>" /etc/apache2/sites-available/000-default.conf; then
            sed -i '/<\/VirtualHost>/i \    <Directory /var/www/html>\n        AllowOverride All\n        Require all granted\n    </Directory>' /etc/apache2/sites-available/000-default.conf
        fi
    fi
else
    echo "  .htaccess not found (may not be needed)"
fi
echo ""

# 8. Check database connectivity
info "[8/10] Checking database connectivity..."

# Extract DB credentials from config.php
DB_HOST=$(grep "DB_HOSTNAME" "$WEBROOT/config.php" | cut -d "'" -f 4 2>/dev/null || echo "localhost")
DB_USER=$(grep "DB_USERNAME" "$WEBROOT/config.php" | cut -d "'" -f 4 2>/dev/null || echo "")
DB_PASS=$(grep "DB_PASSWORD" "$WEBROOT/config.php" | cut -d "'" -f 4 2>/dev/null || echo "")
DB_NAME=$(grep "DB_DATABASE" "$WEBROOT/config.php" | cut -d "'" -f 4 2>/dev/null || echo "")

if [ -n "$DB_USER" ] && [ -n "$DB_NAME" ]; then
    echo "  Database: $DB_NAME"
    echo "  User: $DB_USER"
    echo "  Host: $DB_HOST"
    
    # Test connection
    if mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SELECT 1;" &>/dev/null; then
        success "Database connection OK"
    else
        error "Cannot connect to database!"
        echo "  Check database credentials in: $WEBROOT/config.php"
        echo "  Verify MySQL is running: systemctl status mysql"
    fi
else
    warn "Could not extract database credentials from config.php"
fi
echo ""

# 9. Check config.php URLs
info "[9/10] Checking config.php URL settings..."

HTTP_SERVER=$(grep "HTTP_SERVER" "$WEBROOT/config.php" | grep -v "HTTP_IMAGE" | grep -v "HTTP_ADMIN" | cut -d "'" -f 4 2>/dev/null || echo "")
echo "  HTTP_SERVER: $HTTP_SERVER"

# Get actual server IP
SERVER_IP=$(hostname -I | awk '{print $1}')
echo "  Server IP: $SERVER_IP"

if [ -n "$HTTP_SERVER" ]; then
    if echo "$HTTP_SERVER" | grep -q "$SERVER_IP"; then
        success "URL configuration looks correct"
    else
        warn "URL in config.php may not match server IP"
        echo "  Config has: $HTTP_SERVER"
        echo "  Server IP: $SERVER_IP"
        echo ""
        echo "  To fix, edit $WEBROOT/config.php:"
        echo "    define('HTTP_SERVER', 'http://$SERVER_IP/');"
    fi
fi
echo ""

# 10. Restart Apache
info "[10/10] Restarting Apache..."
if systemctl restart apache2; then
    success "Apache restarted successfully"
else
    error "Failed to restart Apache"
    echo "  Check errors: journalctl -xeu apache2"
    exit 1
fi
echo ""

# Final checks
echo "=================================================="
echo "  Diagnostic Information"
echo "=================================================="
echo ""

echo "Apache Status:"
systemctl status apache2 --no-pager -l | head -10
echo ""

echo "Listening Ports:"
netstat -tuln | grep ":80\|:443"
echo ""

echo "Recent Apache Error Log:"
tail -10 /var/log/apache2/error.log 2>/dev/null || echo "  (no recent errors)"
echo ""

echo "=================================================="
echo "  Troubleshooting Complete"
echo "=================================================="
echo ""

info "Try accessing OpenCart now:"
echo "  Main site: http://$(hostname -I | awk '{print $1}')/"
echo "  Admin panel: http://$(hostname -I | awk '{print $1}')/admin"
echo ""

warn "If still having issues:"
echo "  1. Check browser console for specific errors"
echo "  2. Check Apache error log: sudo tail -f /var/log/apache2/error.log"
echo "  3. Test from command line: curl -I http://localhost/"
echo "  4. Check firewall: sudo ufw status"
echo ""
