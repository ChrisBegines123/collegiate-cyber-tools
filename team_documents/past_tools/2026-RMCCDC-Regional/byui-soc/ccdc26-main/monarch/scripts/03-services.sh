#!/bin/bash
# CCDC26 Monarch - Application Service Hardening
# Auto-detect and harden: Apache/Nginx, PHP, MySQL/MariaDB, PostgreSQL,
# Postfix/Dovecot, vsftpd/ProFTPD, BIND/named
# SELF-CONTAINED -- no external dependencies

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; PURPLE='\033[0;35m'; NC='\033[0m'; BOLD='\033[1m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
phase() { echo -e "\n${BOLD}${PURPLE}[PHASE] $1${NC}\n"; }

backup_file() { local f="$1"; [ -f "$f" ] && cp "$f" "${f}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null; }

if [ "$EUID" -ne 0 ]; then error "Must be run as root"; exit 1; fi

INIT_SYSTEM="unknown"
[ -d /run/systemd/system ] && INIT_SYSTEM="systemd"

svc_restart() {
    local s="$1"
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl restart "$s" 2>/dev/null
    else
        service "$s" restart 2>/dev/null
    fi
}

check_active() {
    local s="$1"
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl is-active "$s" &>/dev/null && return 0
    fi
    pgrep -x "$s" &>/dev/null && return 0
    return 1
}

START_TIME=$(date +%s)
echo -e "\n${BOLD}${GREEN}CCDC26 Monarch - Application Service Hardening${NC}\n"

#=============================================================================
phase "Apache Hardening"
#=============================================================================
APACHE_SVC=""
check_active apache2 && APACHE_SVC="apache2"
check_active httpd && APACHE_SVC="httpd"

if [ -n "$APACHE_SVC" ]; then
    info "Apache detected ($APACHE_SVC), hardening..."

    # Find config directory
    APACHE_CONF=""
    [ -d /etc/apache2 ] && APACHE_CONF="/etc/apache2"
    [ -d /etc/httpd ] && APACHE_CONF="/etc/httpd"

    if [ -n "$APACHE_CONF" ]; then
        SECURITY_CONF="$APACHE_CONF/conf-available/security.conf"
        [ -d "$APACHE_CONF/conf-available" ] || SECURITY_CONF="$APACHE_CONF/conf.d/security.conf"
        mkdir -p "$(dirname "$SECURITY_CONF")"

        cat > "$SECURITY_CONF" << 'EOF'
ServerTokens Prod
ServerSignature Off
TraceEnable Off
Header always set X-Content-Type-Options nosniff
Header always set X-Frame-Options SAMEORIGIN
Header always set X-XSS-Protection "1; mode=block"
FileETag None
EOF
        # Enable if Debian-style
        [ -x /usr/sbin/a2enconf ] && a2enconf security 2>/dev/null
        [ -x /usr/sbin/a2enmod ] && a2enmod headers 2>/dev/null

        # Disable directory listing globally
        for conf_file in "$APACHE_CONF"/apache2.conf "$APACHE_CONF"/conf/httpd.conf "$APACHE_CONF"/httpd.conf; do
            if [ -f "$conf_file" ]; then
                backup_file "$conf_file"
                sed -i 's/Options Indexes/Options -Indexes/g' "$conf_file" 2>/dev/null
            fi
        done

        # Disable unnecessary modules
        for mod in autoindex status info cgi cgid; do
            [ -x /usr/sbin/a2dismod ] && a2dismod "$mod" 2>/dev/null
        done

        svc_restart "$APACHE_SVC"
        ok "Apache hardened"
    fi
else
    info "Apache not running -- skipping"
fi

#=============================================================================
phase "Nginx Hardening"
#=============================================================================
if check_active nginx; then
    info "Nginx detected, hardening..."
    NGINX_CONF="/etc/nginx/nginx.conf"

    if [ -f "$NGINX_CONF" ]; then
        backup_file "$NGINX_CONF"

        # Hide version
        if ! grep -q "server_tokens off" "$NGINX_CONF"; then
            sed -i '/http {/a\    server_tokens off;' "$NGINX_CONF" 2>/dev/null
        fi

        # Add security headers via snippet
        mkdir -p /etc/nginx/snippets
        cat > /etc/nginx/snippets/security-headers.conf << 'EOF'
add_header X-Content-Type-Options nosniff always;
add_header X-Frame-Options SAMEORIGIN always;
add_header X-XSS-Protection "1; mode=block" always;
EOF

        # Disable autoindex in all server blocks
        find /etc/nginx -name "*.conf" -exec sed -i 's/autoindex on/autoindex off/g' {} \; 2>/dev/null

        nginx -t 2>/dev/null && svc_restart nginx
        ok "Nginx hardened"
    fi
else
    info "Nginx not running -- skipping"
fi

#=============================================================================
phase "PHP Hardening"
#=============================================================================
PHP_INI_FOUND=false
for php_ini in /etc/php/*/apache2/php.ini /etc/php/*/fpm/php.ini /etc/php/*/cli/php.ini \
               /etc/php.ini /etc/php5/apache2/php.ini; do
    [ -f "$php_ini" ] || continue
    PHP_INI_FOUND=true
    backup_file "$php_ini"
    info "Hardening $php_ini..."

    sed -i 's/^expose_php.*/expose_php = Off/' "$php_ini" 2>/dev/null
    sed -i 's/^display_errors.*/display_errors = Off/' "$php_ini" 2>/dev/null
    sed -i 's/^display_startup_errors.*/display_startup_errors = Off/' "$php_ini" 2>/dev/null
    sed -i 's/^allow_url_fopen.*/allow_url_fopen = Off/' "$php_ini" 2>/dev/null
    sed -i 's/^allow_url_include.*/allow_url_include = Off/' "$php_ini" 2>/dev/null
    sed -i 's/^session.cookie_httponly.*/session.cookie_httponly = 1/' "$php_ini" 2>/dev/null
    sed -i 's/^session.use_strict_mode.*/session.use_strict_mode = 1/' "$php_ini" 2>/dev/null

    # Disable dangerous functions
    DISABLE_FUNCS="exec,passthru,shell_exec,system,proc_open,popen,parse_ini_file,show_source,eval"
    if grep -q "^disable_functions" "$php_ini"; then
        sed -i "s/^disable_functions.*/disable_functions = $DISABLE_FUNCS/" "$php_ini" 2>/dev/null
    else
        echo "disable_functions = $DISABLE_FUNCS" >> "$php_ini"
    fi
done

if $PHP_INI_FOUND; then
    # Restart PHP-FPM if running
    for fpm in php-fpm php8.2-fpm php8.1-fpm php8.0-fpm php7.4-fpm; do
        check_active "$fpm" && svc_restart "$fpm"
    done
    [ -n "$APACHE_SVC" ] && svc_restart "$APACHE_SVC" 2>/dev/null
    ok "PHP hardened"
else
    info "No PHP installation found -- skipping"
fi

#=============================================================================
phase "MySQL/MariaDB Hardening"
#=============================================================================
MYSQL_SVC=""
check_active mysql && MYSQL_SVC="mysql"
check_active mariadb && MYSQL_SVC="mariadb"
check_active mysqld && MYSQL_SVC="mysqld"

if [ -n "$MYSQL_SVC" ]; then
    info "MySQL/MariaDB detected ($MYSQL_SVC), hardening..."

    # Find my.cnf
    MYCNF=""
    for candidate in /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/mariadb.conf.d/50-server.cnf \
                     /etc/my.cnf.d/server.cnf /etc/my.cnf; do
        [ -f "$candidate" ] && MYCNF="$candidate" && break
    done

    if [ -n "$MYCNF" ]; then
        backup_file "$MYCNF"

        # Ensure bind-address and skip-networking
        if ! grep -q "^bind-address" "$MYCNF"; then
            sed -i '/^\[mysqld\]/a bind-address = 127.0.0.1' "$MYCNF" 2>/dev/null
        else
            sed -i 's/^bind-address.*/bind-address = 127.0.0.1/' "$MYCNF" 2>/dev/null
        fi

        if ! grep -q "^local-infile" "$MYCNF"; then
            sed -i '/^\[mysqld\]/a local-infile = 0' "$MYCNF" 2>/dev/null
        fi

        if ! grep -q "^symbolic-links" "$MYCNF"; then
            sed -i '/^\[mysqld\]/a symbolic-links = 0' "$MYCNF" 2>/dev/null
        fi
    fi

    # Secure SQL commands
    if command -v mysql &>/dev/null; then
        info "Running MySQL security commands..."
        mysql -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null
        mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>/dev/null
        mysql -e "DROP DATABASE IF EXISTS test;" 2>/dev/null
        mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" 2>/dev/null
        mysql -e "FLUSH PRIVILEGES;" 2>/dev/null
    fi

    svc_restart "$MYSQL_SVC" 2>/dev/null
    ok "MySQL/MariaDB hardened"
else
    info "MySQL/MariaDB not running -- skipping"
fi

#=============================================================================
phase "PostgreSQL Hardening"
#=============================================================================
if check_active postgresql || check_active postgres; then
    info "PostgreSQL detected, hardening..."

    # Find pg_hba.conf
    PG_HBA=$(find /etc/postgresql -name "pg_hba.conf" 2>/dev/null | head -1)
    [ -z "$PG_HBA" ] && PG_HBA=$(find /var/lib/pgsql -name "pg_hba.conf" 2>/dev/null | head -1)

    if [ -n "$PG_HBA" ]; then
        backup_file "$PG_HBA"
        info "Hardening $PG_HBA..."

        # Replace trust with md5 for local connections (not peer for local socket)
        sed -i 's/\btrust\b/md5/g' "$PG_HBA" 2>/dev/null

        # Find postgresql.conf
        PG_CONF=$(dirname "$PG_HBA")/postgresql.conf
        if [ -f "$PG_CONF" ]; then
            backup_file "$PG_CONF"
            # Ensure logging
            if ! grep -q "^log_connections" "$PG_CONF"; then
                echo "log_connections = on" >> "$PG_CONF"
            fi
            if ! grep -q "^log_disconnections" "$PG_CONF"; then
                echo "log_disconnections = on" >> "$PG_CONF"
            fi
            # Bind to localhost unless needed
            sed -i "s/^#*listen_addresses.*/listen_addresses = 'localhost'/" "$PG_CONF" 2>/dev/null
        fi

        svc_restart postgresql 2>/dev/null
        ok "PostgreSQL hardened"
    fi
else
    info "PostgreSQL not running -- skipping"
fi

#=============================================================================
phase "Postfix Hardening"
#=============================================================================
if check_active postfix || pgrep -x master &>/dev/null; then
    info "Postfix detected, hardening..."
    POSTFIX_MAIN="/etc/postfix/main.cf"

    if [ -f "$POSTFIX_MAIN" ]; then
        backup_file "$POSTFIX_MAIN"

        # Disable open relay
        postconf -e "smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination" 2>/dev/null
        postconf -e "mynetworks = 127.0.0.0/8 [::1]/128" 2>/dev/null
        postconf -e "smtpd_helo_required = yes" 2>/dev/null
        postconf -e "disable_vrfy_command = yes" 2>/dev/null
        postconf -e "smtpd_banner = \$myhostname ESMTP" 2>/dev/null

        svc_restart postfix 2>/dev/null
        ok "Postfix hardened"
    fi
else
    info "Postfix not running -- skipping"
fi

#=============================================================================
phase "Dovecot Hardening"
#=============================================================================
if check_active dovecot; then
    info "Dovecot detected, hardening..."

    DOVECOT_CONF="/etc/dovecot/dovecot.conf"
    DOVECOT_LOCAL="/etc/dovecot/local.conf"

    cat > "$DOVECOT_LOCAL" << 'EOF'
# CCDC26 Dovecot Hardening
disable_plaintext_auth = yes
ssl = required
login_greeting = Mail Server Ready
EOF

    svc_restart dovecot 2>/dev/null
    ok "Dovecot hardened"
else
    info "Dovecot not running -- skipping"
fi

#=============================================================================
phase "FTP Hardening (vsftpd/ProFTPD)"
#=============================================================================
if check_active vsftpd; then
    info "vsftpd detected, hardening..."
    VSFTPD_CONF="/etc/vsftpd.conf"
    [ -f "$VSFTPD_CONF" ] || VSFTPD_CONF="/etc/vsftpd/vsftpd.conf"

    if [ -f "$VSFTPD_CONF" ]; then
        backup_file "$VSFTPD_CONF"
        sed -i 's/^anonymous_enable=.*/anonymous_enable=NO/' "$VSFTPD_CONF" 2>/dev/null
        sed -i 's/^#*chroot_local_user=.*/chroot_local_user=YES/' "$VSFTPD_CONF" 2>/dev/null

        if ! grep -q "^allow_writeable_chroot" "$VSFTPD_CONF"; then
            echo "allow_writeable_chroot=YES" >> "$VSFTPD_CONF"
        fi
        if ! grep -q "^local_umask" "$VSFTPD_CONF"; then
            echo "local_umask=022" >> "$VSFTPD_CONF"
        fi
        if ! grep -q "^ftpd_banner" "$VSFTPD_CONF"; then
            echo "ftpd_banner=FTP Server Ready" >> "$VSFTPD_CONF"
        fi
        if ! grep -q "^xferlog_enable" "$VSFTPD_CONF"; then
            echo "xferlog_enable=YES" >> "$VSFTPD_CONF"
        fi

        svc_restart vsftpd 2>/dev/null
        ok "vsftpd hardened"
    fi
fi

if check_active proftpd; then
    info "ProFTPD detected, hardening..."
    PROFTPD_CONF="/etc/proftpd/proftpd.conf"
    [ -f "$PROFTPD_CONF" ] || PROFTPD_CONF="/etc/proftpd.conf"

    if [ -f "$PROFTPD_CONF" ]; then
        backup_file "$PROFTPD_CONF"
        sed -i 's/^ServerIdent.*/ServerIdent on "FTP Server Ready"/' "$PROFTPD_CONF" 2>/dev/null

        if ! grep -q "^DefaultRoot" "$PROFTPD_CONF"; then
            echo "DefaultRoot ~" >> "$PROFTPD_CONF"
        fi

        svc_restart proftpd 2>/dev/null
        ok "ProFTPD hardened"
    fi
fi

if ! check_active vsftpd && ! check_active proftpd; then
    info "No FTP server running -- skipping"
fi

#=============================================================================
phase "BIND/named Hardening"
#=============================================================================
if check_active named || check_active bind9; then
    info "BIND/named detected, hardening..."

    NAMED_CONF=""
    for candidate in /etc/named.conf /etc/bind/named.conf.options /etc/bind/named.conf; do
        [ -f "$candidate" ] && NAMED_CONF="$candidate" && break
    done

    if [ -n "$NAMED_CONF" ]; then
        backup_file "$NAMED_CONF"

        # Add options if not present
        if ! grep -q "allow-transfer" "$NAMED_CONF"; then
            sed -i '/options {/a\    allow-transfer { none; };' "$NAMED_CONF" 2>/dev/null
        fi
        if ! grep -q "version" "$NAMED_CONF"; then
            sed -i '/options {/a\    version "not disclosed";' "$NAMED_CONF" 2>/dev/null
        fi
        if ! grep -q "recursion" "$NAMED_CONF"; then
            sed -i '/options {/a\    recursion no;' "$NAMED_CONF" 2>/dev/null
        fi

        named-checkconf 2>/dev/null && svc_restart named 2>/dev/null || svc_restart bind9 2>/dev/null
        ok "BIND/named hardened"
    fi
else
    info "BIND/named not running -- skipping"
fi

#=============================================================================
# SUMMARY
#=============================================================================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo ""
ok "Service hardening complete in ${DURATION}s"
