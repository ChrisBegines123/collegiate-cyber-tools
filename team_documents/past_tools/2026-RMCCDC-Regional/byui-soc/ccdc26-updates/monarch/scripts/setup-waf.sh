#!/bin/bash
# CCDC26 Monarch - ModSecurity WAF Setup with OWASP CRS
# Installs ModSecurity on Apache or Nginx with OWASP Core Rule Set v4.
# Defaults to DETECTIONONLY mode -- logs attacks without blocking requests.
# This is safer for competition scoring. Switch to blocking mode only after
# verifying that the scoring engine's requests are not flagged.
# SELF-CONTAINED -- no external dependencies.

set -uo pipefail

#=============================================================================
# INLINE HELPERS
#=============================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; PURPLE='\033[0;35m'; NC='\033[0m'; BOLD='\033[1m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
phase() { echo -e "\n${BOLD}${PURPLE}========================================${NC}"; echo -e "${BOLD}${PURPLE}[PHASE] $1${NC}"; echo -e "${BOLD}${PURPLE}========================================${NC}\n"; }

backup_file() {
    local f="$1"
    [ -f "$f" ] && cp "$f" "${f}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null
}

if [ "$EUID" -ne 0 ]; then error "Must be run as root"; exit 1; fi

# Distro detection
DISTRO_FAMILY="unknown"; PKG_MGR="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        ubuntu|debian|kali|mint|pop) DISTRO_FAMILY="debian"; PKG_MGR="apt" ;;
        rhel|centos|fedora|rocky|alma|oracle)
            DISTRO_FAMILY="rhel"
            command -v dnf &>/dev/null && PKG_MGR="dnf" || PKG_MGR="yum"
            ;;
    esac
fi

CRS_VERSION="4.7.0"
CRS_URL="https://github.com/coreruleset/coreruleset/archive/refs/tags/v${CRS_VERSION}.tar.gz"
CRS_DIR="/etc/modsecurity/crs"
AUDIT_LOG="/var/log/modsecurity/audit.log"

START_TIME=$(date +%s)
echo ""
echo -e "${BOLD}${GREEN}CCDC26 Monarch - ModSecurity WAF Setup${NC}"
echo -e "${BOLD}Host: $(hostname) | $(date) | $DISTRO_FAMILY / $PKG_MGR${NC}"
echo ""

#=============================================================================
phase "1 - Detect Web Server"
#=============================================================================

WEB_SERVER="none"
if pgrep -x apache2 &>/dev/null || pgrep -x httpd &>/dev/null; then
    WEB_SERVER="apache"
    ok "Apache detected"
elif pgrep -x nginx &>/dev/null; then
    WEB_SERVER="nginx"
    ok "Nginx detected"
fi

if [ "$WEB_SERVER" = "none" ]; then
    error "Neither Apache nor Nginx is running. Start your web server first."
    exit 0
fi

#=============================================================================
phase "2 - Install ModSecurity"
#=============================================================================

if [ "$WEB_SERVER" = "apache" ]; then
    case "$PKG_MGR" in
        apt)
            info "Installing libapache2-mod-security2..."
            apt-get update -qq
            apt-get install -y -qq libapache2-mod-security2 &>/dev/null
            a2enmod security2 &>/dev/null
            ;;
        dnf|yum)
            info "Installing mod_security..."
            $PKG_MGR install -y -q mod_security mod_security_crs &>/dev/null
            ;;
    esac
    ok "ModSecurity module installed for Apache"
elif [ "$WEB_SERVER" = "nginx" ]; then
    case "$PKG_MGR" in
        apt)
            info "Installing libnginx-mod-http-modsecurity..."
            apt-get update -qq
            apt-get install -y -qq libnginx-mod-http-modsecurity &>/dev/null
            ;;
        dnf|yum)
            info "Installing nginx-mod-modsecurity..."
            $PKG_MGR install -y -q nginx-mod-modsecurity &>/dev/null
            ;;
    esac
    ok "ModSecurity module installed for Nginx"
fi

#=============================================================================
phase "3 - Download OWASP Core Rule Set"
#=============================================================================

mkdir -p /etc/modsecurity "$CRS_DIR" /var/log/modsecurity

# Temporary firewall punch for CRS download
info "Opening outbound HTTP/HTTPS for CRS download..."
if command -v iptables &>/dev/null; then
    iptables -I OUTPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null
    iptables -I OUTPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null
    IPTABLES_PUNCHED=true
else
    IPTABLES_PUNCHED=false
fi

info "Downloading OWASP CRS v${CRS_VERSION}..."
TMP_CRS=$(mktemp -d)
if curl -sL "$CRS_URL" -o "$TMP_CRS/crs.tar.gz" && tar -xzf "$TMP_CRS/crs.tar.gz" -C "$TMP_CRS"; then
    cp -r "$TMP_CRS/coreruleset-${CRS_VERSION}/rules/"* "$CRS_DIR/"
    cp "$TMP_CRS/coreruleset-${CRS_VERSION}/crs-setup.conf.example" /etc/modsecurity/crs-setup.conf
    ok "OWASP CRS v${CRS_VERSION} installed to $CRS_DIR"
else
    warn "CRS download failed -- ModSecurity will run without CRS rules"
fi
rm -rf "$TMP_CRS"

if [ "$IPTABLES_PUNCHED" = true ]; then
    info "Closing temporary outbound firewall holes..."
    iptables -D OUTPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null
    iptables -D OUTPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null
fi

#=============================================================================
phase "4 - Configure ModSecurity"
#=============================================================================

# Base ModSecurity configuration
MODSEC_CONF="/etc/modsecurity/modsecurity.conf"
if [ -f /etc/modsecurity/modsecurity.conf-recommended ]; then
    cp /etc/modsecurity/modsecurity.conf-recommended "$MODSEC_CONF"
fi

if [ -f "$MODSEC_CONF" ]; then
    backup_file "$MODSEC_CONF"
    sed -i 's/^SecRuleEngine .*/SecRuleEngine DetectionOnly/' "$MODSEC_CONF"
    ok "SecRuleEngine set to DetectionOnly (log-only mode -- safe for scoring)"
    info "To enable blocking: edit $MODSEC_CONF and set: SecRuleEngine On"
else
    info "Writing fresh ModSecurity config..."
    cat > "$MODSEC_CONF" << 'MODEOF'
# SecRuleEngine On             -- blocking mode (active protection)
# SecRuleEngine DetectionOnly  -- log-only mode (DEFAULT -- safe for scoring)
SecRuleEngine DetectionOnly
SecRequestBodyAccess On
SecRequestBodyLimit 13107200
SecRequestBodyNoFilesLimit 131072
SecResponseBodyAccess Off
SecTmpDir /tmp/
SecDataDir /tmp/
SecAuditEngine RelevantOnly
SecAuditLogRelevantStatus "^(?:5|4(?!04))"
SecAuditLogType Serial
SecAuditLogParts ABCEFHJKZ
SecArgumentSeparator &
SecCookieFormat 0
SecUnicodeMapFile unicode.mapping 20127
SecStatusEngine Off
MODEOF
    ok "Fresh ModSecurity config written"
fi

# Set audit log path (Splunk will ingest this)
if grep -q '^SecAuditLog' "$MODSEC_CONF"; then
    sed -i "s|^SecAuditLog .*|SecAuditLog $AUDIT_LOG|" "$MODSEC_CONF"
else
    echo "SecAuditLog $AUDIT_LOG" >> "$MODSEC_CONF"
fi
ok "Audit log set to $AUDIT_LOG"

# CRS setup tweaks for CCDC (low paranoia = fewer false positives)
if [ -f /etc/modsecurity/crs-setup.conf ]; then
    backup_file /etc/modsecurity/crs-setup.conf
    sed -i 's/^#.*setvar:tx.paranoia_level=1/setvar:tx.paranoia_level=1/' /etc/modsecurity/crs-setup.conf
    if ! grep -q 'tx.paranoia_level' /etc/modsecurity/crs-setup.conf; then
        echo 'SecAction "id:900000, phase:1, pass, t:none, nolog, setvar:tx.paranoia_level=1"' >> /etc/modsecurity/crs-setup.conf
    fi
    ok "CRS paranoia level set to 1 (minimal false positives)"
fi

#=============================================================================
phase "5 - Wire ModSecurity into Web Server"
#=============================================================================

if [ "$WEB_SERVER" = "apache" ]; then
    APACHE_MODSEC="/etc/apache2/mods-enabled/security2.conf"
    [ ! -f "$APACHE_MODSEC" ] && APACHE_MODSEC="/etc/httpd/conf.d/mod_security.conf"
    if [ -f "$APACHE_MODSEC" ]; then
        backup_file "$APACHE_MODSEC"
    fi
    cat > /etc/apache2/conf-available/modsecurity-crs.conf 2>/dev/null << AEOF || true
<IfModule security2_module>
    IncludeOptional /etc/modsecurity/modsecurity.conf
    IncludeOptional /etc/modsecurity/crs-setup.conf
    IncludeOptional ${CRS_DIR}/*.conf
</IfModule>
AEOF
    a2enconf modsecurity-crs &>/dev/null || true

    info "Restarting Apache..."
    if apachectl configtest 2>&1 | grep -q "Syntax OK"; then
        systemctl restart apache2 2>/dev/null || systemctl restart httpd 2>/dev/null
        ok "Apache restarted with ModSecurity + CRS"
    else
        error "Apache config test failed -- check manually: apachectl configtest"
    fi

elif [ "$WEB_SERVER" = "nginx" ]; then
    NGINX_CONF="/etc/nginx/nginx.conf"
    backup_file "$NGINX_CONF"
    if ! grep -q 'modsecurity on' "$NGINX_CONF" 2>/dev/null; then
        sed -i '/http {/a\    modsecurity on;\n    modsecurity_rules_file /etc/modsecurity/modsecurity.conf;' "$NGINX_CONF"
    fi
    # Include CRS in the modsecurity config
    if ! grep -q 'crs-setup.conf' "$MODSEC_CONF"; then
        echo "Include /etc/modsecurity/crs-setup.conf" >> "$MODSEC_CONF"
        echo "Include ${CRS_DIR}/*.conf" >> "$MODSEC_CONF"
    fi

    info "Restarting Nginx..."
    if nginx -t 2>&1 | grep -q "successful"; then
        systemctl restart nginx 2>/dev/null
        ok "Nginx restarted with ModSecurity + CRS"
    else
        error "Nginx config test failed -- check manually: nginx -t"
    fi
fi

#=============================================================================
# SUMMARY
#=============================================================================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
phase "WAF Setup Complete"
ok "Finished in ${DURATION}s"
echo ""
echo "CONFIGURATION:"
echo "  Web server:   $WEB_SERVER"
echo "  ModSecurity:  $MODSEC_CONF"
echo "  CRS rules:    $CRS_DIR/"
echo "  Audit log:    $AUDIT_LOG  (point Splunk here)"
echo "  Mode:         DETECTIONONLY (log-only -- attacks are logged but NOT blocked)"
echo ""
echo "SPLUNK INTEGRATION (add to inputs.conf):"
echo "  [monitor://$AUDIT_LOG]"
echo "  sourcetype = modsecurity"
echo "  index = security"
echo ""
echo "SWITCHING TO BLOCKING MODE:"
echo "  1. Verify scored services are green on Stadium"
echo "  2. Edit $MODSEC_CONF and change: SecRuleEngine On"
echo "  3. Restart web server: systemctl restart apache2  (or nginx)"
echo "  4. Re-check Stadium immediately -- if scoring drops, revert to DetectionOnly"
echo ""
echo "TUNING:"
echo "  - Paranoia level is 1 (lowest). Increase in /etc/modsecurity/crs-setup.conf if needed"
echo "  - To whitelist an IP: SecRule REMOTE_ADDR \"@ipMatch 10.0.0.1\" \"id:1,phase:1,allow,nolog\""
echo ""
