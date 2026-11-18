#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Apache/Nginx Hardening
# Secure web server configurations

source "$(dirname "$0")/../utils/common.sh"
require_root

header "Web Server Hardening"

#=============================================================================
# DETECT WEB SERVER
#=============================================================================
detect_webserver() {
    if command -v apache2 &>/dev/null || command -v httpd &>/dev/null; then
        if systemctl is-active apache2 &>/dev/null || systemctl is-active httpd &>/dev/null; then
            WEBSERVER="apache"
            [ -d /etc/apache2 ] && APACHE_DIR="/etc/apache2" || APACHE_DIR="/etc/httpd"
            return 0
        fi
    fi
    
    if command -v nginx &>/dev/null; then
        if systemctl is-active nginx &>/dev/null; then
            WEBSERVER="nginx"
            NGINX_DIR="/etc/nginx"
            return 0
        fi
    fi
    
    WEBSERVER="none"
    return 1
}

#=============================================================================
# APACHE HARDENING
#=============================================================================
harden_apache() {
    header "Hardening Apache"
    
    local conf_dir="$APACHE_DIR"
    local security_conf=""
    
    # Find security config location
    if [ -d "$conf_dir/conf-available" ]; then
        security_conf="$conf_dir/conf-available/security.conf"
    elif [ -d "$conf_dir/conf.d" ]; then
        security_conf="$conf_dir/conf.d/security.conf"
    else
        security_conf="$conf_dir/security.conf"
    fi
    
    backup_file "$security_conf"
    
    cat > "$security_conf" << 'EOF'
# CCDC26 Apache Security Configuration

# Hide version info
ServerTokens Prod
ServerSignature Off

# Disable directory listing
<Directory />
    Options -Indexes -FollowSymLinks
    AllowOverride None
    Require all denied
</Directory>

# Security headers
<IfModule mod_headers.c>
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    Header always unset X-Powered-By
    Header always unset Server
</IfModule>

# Disable TRACE method
TraceEnable Off

# Timeout settings
Timeout 60
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5

# Limit request size
LimitRequestBody 10485760
LimitRequestFields 50
LimitRequestFieldSize 8190
LimitRequestLine 8190

# Disable dangerous modules (if enabled)
# Uncomment as needed:
# LoadModule info_module modules/mod_info.so
# LoadModule status_module modules/mod_status.so
# LoadModule userdir_module modules/mod_userdir.so
EOF

    # Enable security config (Debian/Ubuntu)
    if [ -d "$conf_dir/conf-enabled" ]; then
        ln -sf "$security_conf" "$conf_dir/conf-enabled/security.conf"
    fi
    
    # Disable unnecessary modules (Debian/Ubuntu)
    if command -v a2dismod &>/dev/null; then
        a2dismod status 2>/dev/null
        a2dismod info 2>/dev/null
        a2dismod userdir 2>/dev/null
        a2enmod headers 2>/dev/null
    fi
    
    # Find and secure document root
    info "Checking document roots..."
    local docroots=$(grep -rh "DocumentRoot" "$conf_dir" 2>/dev/null | awk '{print $2}' | tr -d '"' | sort -u)
    
    for docroot in $docroots; do
        if [ -d "$docroot" ]; then
            info "Securing document root: $docroot"
            
            # Remove dangerous files
            find "$docroot" -name "*.bak" -delete 2>/dev/null
            find "$docroot" -name "*.old" -delete 2>/dev/null
            find "$docroot" -name ".git" -type d -exec rm -rf {} + 2>/dev/null
            find "$docroot" -name ".svn" -type d -exec rm -rf {} + 2>/dev/null
            
            # Check for web shells
            info "Scanning for potential web shells..."
            find "$docroot" -type f -name "*.php" -exec grep -l "eval\|base64_decode\|system\|exec\|shell_exec\|passthru" {} \; 2>/dev/null | while read -r file; do
                log_finding "Potential web shell: $file"
            done
        fi
    done
    
    # Test configuration
    if apache2ctl configtest 2>/dev/null || httpd -t 2>/dev/null; then
        success "Apache configuration valid"
        
        # Restart
        systemctl restart apache2 2>/dev/null || systemctl restart httpd 2>/dev/null
        success "Apache restarted"
    else
        error "Apache configuration has errors!"
    fi
    
    log_action "Hardened Apache"
}

#=============================================================================
# NGINX HARDENING
#=============================================================================
harden_nginx() {
    header "Hardening Nginx"
    
    local nginx_conf="/etc/nginx/nginx.conf"
    local security_conf="/etc/nginx/conf.d/security.conf"
    
    backup_file "$nginx_conf"
    
    # Create security config
    cat > "$security_conf" << 'EOF'
# CCDC26 Nginx Security Configuration

# Hide version
server_tokens off;

# Security headers
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;

# Disable unwanted HTTP methods
if ($request_method !~ ^(GET|HEAD|POST)$) {
    return 405;
}

# Block common exploits
location ~* "(eval\(|base64_|<script|<iframe)" {
    deny all;
}

# Block web shells
location ~* "(c99|r57|shell|cmd|passthru|exec|system)" {
    deny all;
}

# Protect sensitive files
location ~ /\. {
    deny all;
}

location ~* \.(git|svn|htaccess|htpasswd|bak|old|swp|sql)$ {
    deny all;
}

# Limit request size
client_max_body_size 10M;
client_body_buffer_size 128k;

# Timeouts
client_body_timeout 10;
client_header_timeout 10;
keepalive_timeout 5 5;
send_timeout 10;

# Limit connections
limit_conn_zone $binary_remote_addr zone=addr:10m;
limit_conn addr 100;
EOF

    # Add include to main config if not present
    if ! grep -q "include.*security.conf" "$nginx_conf"; then
        # Add include in http block
        sed -i '/http {/a\    include /etc/nginx/conf.d/security.conf;' "$nginx_conf"
    fi
    
    # Disable autoindex globally
    sed -i 's/autoindex on/autoindex off/g' /etc/nginx/sites-available/* 2>/dev/null
    sed -i 's/autoindex on/autoindex off/g' /etc/nginx/sites-enabled/* 2>/dev/null
    
    # Find and secure document roots
    info "Checking document roots..."
    local docroots=$(grep -rh "root " /etc/nginx 2>/dev/null | grep -v "#" | awk '{print $2}' | tr -d ';' | sort -u)
    
    for docroot in $docroots; do
        if [ -d "$docroot" ]; then
            info "Securing document root: $docroot"
            
            # Remove dangerous files
            find "$docroot" -name "*.bak" -delete 2>/dev/null
            find "$docroot" -name "*.old" -delete 2>/dev/null
            find "$docroot" -name ".git" -type d -exec rm -rf {} + 2>/dev/null
            
            # Check for web shells
            info "Scanning for potential web shells..."
            find "$docroot" -type f -name "*.php" -exec grep -l "eval\|base64_decode\|system\|exec\|shell_exec" {} \; 2>/dev/null | while read -r file; do
                log_finding "Potential web shell: $file"
            done
        fi
    done
    
    # Test configuration
    if nginx -t 2>/dev/null; then
        success "Nginx configuration valid"
        systemctl restart nginx
        success "Nginx restarted"
    else
        error "Nginx configuration has errors!"
    fi
    
    log_action "Hardened Nginx"
}

#=============================================================================
# SECURE PHP
#=============================================================================
secure_php() {
    header "Securing PHP"
    
    # Find php.ini locations
    local php_inis=$(find /etc -name "php.ini" 2>/dev/null)
    
    if [ -z "$php_inis" ]; then
        warn "No php.ini found"
        return
    fi
    
    for php_ini in $php_inis; do
        info "Securing: $php_ini"
        backup_file "$php_ini"
        
        # Disable dangerous functions
        sed -i 's/^disable_functions.*/disable_functions = exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source,pcntl_exec/' "$php_ini"
        
        # Hide PHP version
        sed -i 's/^expose_php.*/expose_php = Off/' "$php_ini"
        
        # Disable remote file inclusion
        sed -i 's/^allow_url_fopen.*/allow_url_fopen = Off/' "$php_ini"
        sed -i 's/^allow_url_include.*/allow_url_include = Off/' "$php_ini"
        
        # Limit resources
        sed -i 's/^max_execution_time.*/max_execution_time = 30/' "$php_ini"
        sed -i 's/^max_input_time.*/max_input_time = 60/' "$php_ini"
        sed -i 's/^memory_limit.*/memory_limit = 128M/' "$php_ini"
        sed -i 's/^post_max_size.*/post_max_size = 10M/' "$php_ini"
        sed -i 's/^upload_max_filesize.*/upload_max_filesize = 10M/' "$php_ini"
        
        # Session security
        sed -i 's/^session.cookie_httponly.*/session.cookie_httponly = 1/' "$php_ini"
        sed -i 's/^session.use_strict_mode.*/session.use_strict_mode = 1/' "$php_ini"
        sed -i 's/^session.cookie_secure.*/session.cookie_secure = 1/' "$php_ini"
        
        # Error handling
        sed -i 's/^display_errors.*/display_errors = Off/' "$php_ini"
        sed -i 's/^log_errors.*/log_errors = On/' "$php_ini"
        
        success "Secured: $php_ini"
    done
    
    # Restart PHP-FPM if running
    systemctl restart php*-fpm 2>/dev/null
    
    log_action "Secured PHP configuration"
}

#=============================================================================
# FIND WEB SHELLS
#=============================================================================
find_webshells() {
    header "Scanning for Web Shells"
    
    local webdirs="/var/www /srv/www /home/*/public_html /var/html"
    
    info "Scanning web directories..."
    
    local suspicious_patterns=(
        "eval.*base64_decode"
        "eval.*gzinflate"
        "eval.*str_rot13"
        "shell_exec"
        "passthru"
        "assert.*\$_"
        "preg_replace.*\/e"
        "create_function"
        "call_user_func.*\$_"
        "c99"
        "r57"
        "b374k"
        "weevely"
        "wso"
    )
    
    for dir in $webdirs; do
        [ -d "$dir" ] || continue
        
        info "Scanning: $dir"
        
        for pattern in "${suspicious_patterns[@]}"; do
            find "$dir" -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.php5" \) \
                -exec grep -l "$pattern" {} \; 2>/dev/null | while read -r file; do
                log_finding "Potential web shell ($pattern): $file"
            done
        done
        
        # Check for recently modified PHP files
        info "Recently modified PHP files (last 7 days):"
        find "$dir" -type f -name "*.php" -mtime -7 2>/dev/null | while read -r file; do
            warn "Recent: $file"
        done
    done
}

#=============================================================================
# CHECK WEB PERMISSIONS
#=============================================================================
check_web_permissions() {
    header "Checking Web Directory Permissions"
    
    local webdirs="/var/www /srv/www"
    
    for dir in $webdirs; do
        [ -d "$dir" ] || continue
        
        info "Checking: $dir"
        
        # World-writable directories
        find "$dir" -type d -perm -0002 2>/dev/null | while read -r d; do
            log_finding "World-writable directory: $d"
        done
        
        # World-writable files
        find "$dir" -type f -perm -0002 2>/dev/null | while read -r f; do
            log_finding "World-writable file: $f"
        done
        
        # Files owned by www-data that are writable
        find "$dir" -type f -user www-data -perm -0200 2>/dev/null | head -20
    done
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    detect_webserver
    
    echo ""
    echo "Detected web server: $WEBSERVER"
    echo ""
    echo "Web Server Hardening Options:"
    echo "1) Harden Apache"
    echo "2) Harden Nginx"
    echo "3) Secure PHP"
    echo "4) Find web shells"
    echo "5) Check web permissions"
    echo "6) Harden detected server ($WEBSERVER)"
    echo "7) Run ALL"
    echo ""
    read -p "Select option [1-7]: " choice
    
    case $choice in
        1) harden_apache ;;
        2) harden_nginx ;;
        3) secure_php ;;
        4) find_webshells ;;
        5) check_web_permissions ;;
        6)
            case "$WEBSERVER" in
                apache) harden_apache ;;
                nginx) harden_nginx ;;
                *) error "No web server detected" ;;
            esac
            ;;
        7)
            [ "$WEBSERVER" == "apache" ] && harden_apache
            [ "$WEBSERVER" == "nginx" ] && harden_nginx
            secure_php
            find_webshells
            check_web_permissions
            ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
