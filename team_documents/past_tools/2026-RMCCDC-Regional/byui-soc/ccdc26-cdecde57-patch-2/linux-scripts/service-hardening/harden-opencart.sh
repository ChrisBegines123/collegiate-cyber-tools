#!/bin/bash
#=============================================================================
# OpenCart E-Commerce Hardening Script
#=============================================================================
# Secures OpenCart installation on Ubuntu Ecom Server
#
# Usage:
#   sudo ./harden-opencart.sh [webroot]
#   # Default webroot: /var/www/html
#
# Actions:
#   1. Remove install directory (prevents reinstallation)
#   2. Rename admin directory (obfuscation)
#   3. Set secure file permissions
#   4. Install fail2ban for brute force protection
#   5. Enable Apache security headers
#   6. Create database backup
#
#=============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
WEBROOT="${1:-/var/www/html}"
ADMIN_DIR="$WEBROOT/admin"
NEW_ADMIN_NAME="admin_secure_$(date +%s | tail -c 5)"
NEW_ADMIN_DIR="$WEBROOT/$NEW_ADMIN_NAME"
BACKUP_DIR="/tmp/opencart_backup_$(date +%Y%m%d_%H%M%S)"

# Must be root
if [ "$EUID" -ne 0 ]; then
   error "Must run as root"
   echo "Usage: sudo $0 [webroot]"
   exit 1
fi

echo ""
echo "=================================================="
echo "  OpenCart Security Hardening"
echo "=================================================="
echo ""
echo "Web Root: $WEBROOT"
echo "New Admin Path: /$NEW_ADMIN_NAME"
echo ""

# Verify OpenCart installation
if [ ! -f "$WEBROOT/config.php" ]; then
    error "OpenCart not found at $WEBROOT"
    echo "Specify correct webroot: sudo $0 /path/to/opencart"
    exit 1
fi

info "OpenCart installation found"
echo ""

# Create backup
info "[0/7] Creating backup..."
mkdir -p "$BACKUP_DIR"
if [ -d "$WEBROOT" ]; then
    cp -r "$WEBROOT" "$BACKUP_DIR/"
    echo "  ✓ Backup created: $BACKUP_DIR"
else
    warn "Could not create backup"
fi
echo ""

# 1. Remove install directory
info "[1/7] Removing install directory..."
if [ -d "$WEBROOT/install" ]; then
    rm -rf "$WEBROOT/install"
    echo "  ✓ Removed /install directory"
else
    echo "  - Install directory not found (already removed)"
fi
echo ""

# 2. Rename admin directory
info "[2/7] Renaming admin directory..."
if [ -d "$ADMIN_DIR" ] && [ ! -d "$NEW_ADMIN_DIR" ]; then
    mv "$ADMIN_DIR" "$NEW_ADMIN_DIR"
    echo "  ✓ Admin directory renamed"
    echo "  📁 New path: /$NEW_ADMIN_NAME"
    
    # Update main config.php
    if [ -f "$WEBROOT/config.php" ]; then
        sed -i.bak "s|/admin/|/$NEW_ADMIN_NAME/|g" "$WEBROOT/config.php"
        echo "  ✓ Updated $WEBROOT/config.php"
    fi
    
    # Update admin config.php
    if [ -f "$NEW_ADMIN_DIR/config.php" ]; then
        sed -i.bak "s|/admin/|/$NEW_ADMIN_NAME/|g" "$NEW_ADMIN_DIR/config.php"
        echo "  ✓ Updated $NEW_ADMIN_DIR/config.php"
    fi
    
    warn "IMPORTANT: New admin URL is: http://your-ip/$NEW_ADMIN_NAME"
elif [ -d "$NEW_ADMIN_DIR" ]; then
    echo "  - Admin directory already renamed"
else
    warn "Admin directory not found at $ADMIN_DIR"
fi
echo ""

# 3. Set secure permissions
info "[3/7] Setting secure file permissions..."
# Directories: 755
find "$WEBROOT" -type d -exec chmod 755 {} \; 2>/dev/null || true
# Files: 644
find "$WEBROOT" -type f -exec chmod 644 {} \; 2>/dev/null || true
# Config files: 644 (read-only)
chmod 644 "$WEBROOT/config.php" 2>/dev/null || true
[ -f "$NEW_ADMIN_DIR/config.php" ] && chmod 644 "$NEW_ADMIN_DIR/config.php"
# Writable directories for uploads
chmod -R 777 "$WEBROOT/image/" 2>/dev/null || true
chmod -R 777 "$WEBROOT/system/storage/" 2>/dev/null || true
# Set ownership
chown -R www-data:www-data "$WEBROOT" 2>/dev/null || true
echo "  ✓ Permissions set"
echo "  ✓ Ownership: www-data:www-data"
echo ""

# 4. Install fail2ban
info "[4/7] Installing fail2ban..."
if ! command -v fail2ban-client &>/dev/null; then
    apt-get update -qq
    apt-get install -y fail2ban &>/dev/null
    echo "  ✓ fail2ban installed"
else
    echo "  - fail2ban already installed"
fi

# Create OpenCart jail
cat > /etc/fail2ban/jail.d/opencart.conf << EOF
[opencart-admin]
enabled = true
port = http,https
filter = opencart-admin
logpath = /var/log/apache2/access.log
maxretry = 3
bantime = 3600
findtime = 600
EOF

# Create filter
cat > /etc/fail2ban/filter.d/opencart-admin.conf << EOF
[Definition]
failregex = ^<HOST> .* "POST /$NEW_ADMIN_NAME/.*login.*" (200|302)
ignoreregex =
EOF

systemctl restart fail2ban 2>/dev/null || true
echo "  ✓ fail2ban configured for OpenCart admin"
echo ""

# 5. Enable Apache security headers
info "[5/7] Configuring Apache security headers..."
if command -v a2enmod &>/dev/null; then
    a2enmod headers &>/dev/null || true
    
    # Add security headers to Apache config
    APACHE_CONF="/etc/apache2/sites-available/000-default.conf"
    if [ -f "$APACHE_CONF" ]; then
        # Check if headers already added
        if ! grep -q "X-Frame-Options" "$APACHE_CONF"; then
            # Insert before </VirtualHost>
            sed -i '/<\/VirtualHost>/i \
\    # Security Headers\
\    <IfModule mod_headers.c>\
\        Header always set X-Frame-Options "SAMEORIGIN"\
\        Header always set X-Content-Type-Options "nosniff"\
\        Header always set X-XSS-Protection "1; mode=block"\
\        Header always set Referrer-Policy "strict-origin-when-cross-origin"\
\    </IfModule>' "$APACHE_CONF"
            echo "  ✓ Security headers added to Apache config"
        else
            echo "  - Security headers already configured"
        fi
    fi
else
    warn "Apache not found or not using a2enmod"
fi
echo ""

# 6. Check for suspicious files
info "[6/7] Scanning for suspicious files..."
SUSPICIOUS=$(find "$WEBROOT" -type f -name "*.php" -exec grep -l "eval\|base64_decode.*eval\|system\|exec\|shell_exec" {} \; 2>/dev/null | head -10)
if [ -n "$SUSPICIOUS" ]; then
    warn "Found files with potentially dangerous functions:"
    echo "$SUSPICIOUS" | while read -r file; do
        echo "    $file"
    done
    echo ""
    warn "Review these files manually!"
else
    echo "  ✓ No obvious suspicious files found"
fi
echo ""

# 7. Restart Apache
info "[7/7] Restarting Apache..."
if systemctl restart apache2 2>/dev/null; then
    echo "  ✓ Apache restarted"
elif service apache2 restart 2>/dev/null; then
    echo "  ✓ Apache restarted"
else
    warn "Could not restart Apache automatically"
fi
echo ""

# Summary
echo "=================================================="
echo "  🎯 OpenCart Hardening Complete"
echo "=================================================="
echo ""
echo "✅ Actions Completed:"
echo "  • Removed /install directory"
echo "  • Renamed admin directory to: /$NEW_ADMIN_NAME"
echo "  • Set secure file permissions"
echo "  • Configured fail2ban protection"
echo "  • Enabled Apache security headers"
echo "  • Scanned for suspicious files"
echo ""
echo "⚠️  CRITICAL MANUAL STEPS:"
echo ""
echo "1. LOGIN TO ADMIN PANEL:"
echo "   URL: http://$(hostname -I | awk '{print $1}')/$NEW_ADMIN_NAME"
echo "   Try default credentials: admin / admin"
echo ""
echo "2. CHANGE ADMIN PASSWORD:"
echo "   Navigate to: System → Users → Users"
echo "   Change admin password to team password"
echo ""
echo "3. CHANGE DATABASE PASSWORD:"
echo "   mysql -u root -p"
echo "   ALTER USER 'opencart_user'@'localhost' IDENTIFIED BY 'NewPassword';"
echo "   Then update: $WEBROOT/config.php"
echo ""
echo "4. REVIEW EXTENSIONS:"
echo "   Admin → Extensions → Extensions"
echo "   Disable any suspicious extensions"
echo ""
echo "📁 Backup Location: $BACKUP_DIR"
echo ""
echo "📊 Monitor logs:"
echo "   tail -f /var/log/apache2/access.log | grep \"$NEW_ADMIN_NAME\""
echo ""

info "Done! OpenCart is now more secure."
echo ""
