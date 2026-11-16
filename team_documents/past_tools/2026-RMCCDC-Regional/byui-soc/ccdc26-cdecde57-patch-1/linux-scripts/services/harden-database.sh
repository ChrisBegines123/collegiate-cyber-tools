#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Database Hardening
# Secure MySQL, MariaDB, and PostgreSQL

source "$(dirname "$0")/../utils/common.sh"
require_root

header "Database Hardening"

#=============================================================================
# DETECT DATABASE
#=============================================================================
detect_database() {
    DATABASES=()
    
    if systemctl is-active mysql &>/dev/null || systemctl is-active mariadb &>/dev/null; then
        DATABASES+=("mysql")
    fi
    
    if systemctl is-active postgresql &>/dev/null; then
        DATABASES+=("postgresql")
    fi
    
    if [ ${#DATABASES[@]} -eq 0 ]; then
        warn "No running databases detected"
        return 1
    fi
    
    info "Detected databases: ${DATABASES[*]}"
    return 0
}

#=============================================================================
# MYSQL/MARIADB HARDENING
#=============================================================================
harden_mysql() {
    header "Hardening MySQL/MariaDB"
    
    # Check if running
    if ! systemctl is-active mysql &>/dev/null && ! systemctl is-active mariadb &>/dev/null; then
        error "MySQL/MariaDB is not running"
        return 1
    fi
    
    # Find config directory
    local my_cnf=""
    for conf in /etc/mysql/my.cnf /etc/my.cnf /etc/mysql/mysql.conf.d/mysqld.cnf; do
        if [ -f "$conf" ]; then
            my_cnf="$conf"
            break
        fi
    done
    
    if [ -z "$my_cnf" ]; then
        # Create security config in conf.d
        if [ -d /etc/mysql/conf.d ]; then
            my_cnf="/etc/mysql/conf.d/security.cnf"
        elif [ -d /etc/mysql/mysql.conf.d ]; then
            my_cnf="/etc/mysql/mysql.conf.d/security.cnf"
        else
            my_cnf="/etc/my.cnf.d/security.cnf"
            mkdir -p /etc/my.cnf.d
        fi
    fi
    
    backup_file "$my_cnf"
    
    # Create/append security settings
    cat > "${my_cnf}.security" << 'EOF'
# CCDC26 MySQL/MariaDB Security Configuration

[mysqld]
# Bind to localhost only (change if remote access needed)
bind-address = 127.0.0.1

# Disable local file loading
local-infile = 0

# Disable symbolic links
symbolic-links = 0

# Disable LOAD DATA LOCAL
local_infile = 0

# Log settings
log-error = /var/log/mysql/error.log
general_log = 0
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 2

# Security settings
skip-symbolic-links
secure-file-priv = /var/lib/mysql-files

# Connection limits
max_connections = 100
max_connect_errors = 10
wait_timeout = 600
interactive_timeout = 600

# Password policy (MariaDB/MySQL 5.7+)
# validate_password_policy = STRONG
# validate_password_length = 12
EOF

    if [ -f "$my_cnf" ]; then
        # Append if exists
        cat "${my_cnf}.security" >> "$my_cnf"
        rm "${my_cnf}.security"
    else
        mv "${my_cnf}.security" "$my_cnf"
    fi
    
    success "Configuration updated"
    
    # Interactive security tasks
    info "Performing security checks..."
    
    # Try to connect
    local mysql_cmd="mysql"
    if ! mysql -e "SELECT 1" &>/dev/null; then
        read -sp "Enter MySQL root password: " mysql_pass
        echo
        mysql_cmd="mysql -p$mysql_pass"
    fi
    
    # Check for anonymous users
    info "Checking for anonymous users..."
    local anon_users=$($mysql_cmd -N -e "SELECT User, Host FROM mysql.user WHERE User='';" 2>/dev/null)
    if [ -n "$anon_users" ]; then
        log_finding "Anonymous MySQL users found:"
        echo "$anon_users"
        
        read -p "Remove anonymous users? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            $mysql_cmd -e "DELETE FROM mysql.user WHERE User='';"
            success "Anonymous users removed"
        fi
    else
        success "No anonymous users"
    fi
    
    # Check for remote root login
    info "Checking for remote root access..."
    local remote_root=$($mysql_cmd -N -e "SELECT Host FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>/dev/null)
    if [ -n "$remote_root" ]; then
        log_finding "Remote root access enabled from: $remote_root"
        
        read -p "Disable remote root access? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            $mysql_cmd -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
            success "Remote root access disabled"
        fi
    else
        success "No remote root access"
    fi
    
    # Check for test database
    info "Checking for test database..."
    local test_db=$($mysql_cmd -N -e "SHOW DATABASES LIKE 'test';" 2>/dev/null)
    if [ -n "$test_db" ]; then
        log_finding "Test database exists"
        
        read -p "Remove test database? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            $mysql_cmd -e "DROP DATABASE IF EXISTS test;"
            $mysql_cmd -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
            success "Test database removed"
        fi
    fi
    
    # List all users
    info "Current MySQL users:"
    $mysql_cmd -e "SELECT User, Host, plugin FROM mysql.user;" 2>/dev/null
    
    # Flush privileges
    $mysql_cmd -e "FLUSH PRIVILEGES;" 2>/dev/null
    
    # Restart service
    systemctl restart mysql 2>/dev/null || systemctl restart mariadb 2>/dev/null
    
    success "MySQL/MariaDB hardening complete"
    log_action "Hardened MySQL/MariaDB"
}

#=============================================================================
# POSTGRESQL HARDENING
#=============================================================================
harden_postgresql() {
    header "Hardening PostgreSQL"
    
    if ! systemctl is-active postgresql &>/dev/null; then
        error "PostgreSQL is not running"
        return 1
    fi
    
    # Find PostgreSQL config
    local pg_conf=""
    local pg_hba=""
    local pg_version=""
    
    for version in 16 15 14 13 12 11 10 9.6; do
        if [ -f "/etc/postgresql/$version/main/postgresql.conf" ]; then
            pg_conf="/etc/postgresql/$version/main/postgresql.conf"
            pg_hba="/etc/postgresql/$version/main/pg_hba.conf"
            pg_version="$version"
            break
        fi
    done
    
    # Try RHEL paths
    if [ -z "$pg_conf" ]; then
        for conf in /var/lib/pgsql/data/postgresql.conf /var/lib/postgresql/data/postgresql.conf; do
            if [ -f "$conf" ]; then
                pg_conf="$conf"
                pg_hba="$(dirname "$conf")/pg_hba.conf"
                break
            fi
        done
    fi
    
    if [ -z "$pg_conf" ]; then
        error "Could not find PostgreSQL configuration"
        return 1
    fi
    
    info "Found config: $pg_conf"
    
    backup_file "$pg_conf"
    backup_file "$pg_hba"
    
    # Update postgresql.conf
    info "Updating postgresql.conf..."
    
    # Listen address
    sed -i "s/^#*listen_addresses.*/listen_addresses = 'localhost'/" "$pg_conf"
    
    # Logging
    sed -i "s/^#*log_connections.*/log_connections = on/" "$pg_conf"
    sed -i "s/^#*log_disconnections.*/log_disconnections = on/" "$pg_conf"
    sed -i "s/^#*log_line_prefix.*/log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '/" "$pg_conf"
    
    # SSL (if certs exist)
    if [ -f /etc/ssl/certs/ssl-cert-snakeoil.pem ]; then
        sed -i "s/^#*ssl = .*/ssl = on/" "$pg_conf"
    fi
    
    # Password encryption
    sed -i "s/^#*password_encryption.*/password_encryption = scram-sha-256/" "$pg_conf"
    
    # Secure pg_hba.conf
    info "Updating pg_hba.conf..."
    
    # Create secure pg_hba.conf
    cat > "$pg_hba" << 'EOF'
# CCDC26 PostgreSQL Client Authentication Configuration
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local connections
local   all             postgres                                peer
local   all             all                                     peer

# IPv4 local connections (password required)
host    all             all             127.0.0.1/32            scram-sha-256

# IPv6 local connections
host    all             all             ::1/128                 scram-sha-256

# Reject all other connections
host    all             all             0.0.0.0/0               reject
EOF
    
    success "Configuration updated"
    
    # Database security checks
    info "Performing security checks..."
    
    # List roles
    info "Current PostgreSQL roles:"
    sudo -u postgres psql -c "\du" 2>/dev/null
    
    # Check for superusers
    info "Superuser accounts:"
    sudo -u postgres psql -t -c "SELECT rolname FROM pg_roles WHERE rolsuper = true;" 2>/dev/null
    
    # Check for roles with no password
    info "Checking for roles with password issues..."
    
    # Prompt to change postgres password
    read -p "Change postgres superuser password? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -sp "Enter new postgres password: " new_pass
        echo
        sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD '$new_pass';" 2>/dev/null
        success "Postgres password changed"
    fi
    
    # Restart PostgreSQL
    systemctl restart postgresql
    
    success "PostgreSQL hardening complete"
    log_action "Hardened PostgreSQL"
}

#=============================================================================
# AUDIT DATABASE USERS
#=============================================================================
audit_db_users() {
    header "Auditing Database Users"
    
    # MySQL/MariaDB
    if systemctl is-active mysql &>/dev/null || systemctl is-active mariadb &>/dev/null; then
        info "=== MySQL/MariaDB Users ==="
        mysql -e "SELECT User, Host, plugin, password_expired FROM mysql.user;" 2>/dev/null || \
        mysql -p -e "SELECT User, Host, plugin, password_expired FROM mysql.user;" 2>/dev/null
        
        echo ""
        info "User privileges:"
        mysql -e "SELECT User, Host, Grant_priv, Super_priv, File_priv FROM mysql.user;" 2>/dev/null
    fi
    
    # PostgreSQL
    if systemctl is-active postgresql &>/dev/null; then
        info "=== PostgreSQL Users ==="
        sudo -u postgres psql -c "\du" 2>/dev/null
        
        echo ""
        info "Database permissions:"
        sudo -u postgres psql -c "\l" 2>/dev/null
    fi
}

#=============================================================================
# CHANGE DATABASE PASSWORDS
#=============================================================================
change_db_passwords() {
    header "Changing Database Passwords"
    
    # MySQL/MariaDB
    if systemctl is-active mysql &>/dev/null || systemctl is-active mariadb &>/dev/null; then
        info "=== MySQL/MariaDB Password Changes ==="
        
        read -sp "Enter current MySQL root password (or press enter if none): " current_pass
        echo
        
        local mysql_cmd="mysql"
        [ -n "$current_pass" ] && mysql_cmd="mysql -p$current_pass"
        
        # Get list of users
        local users=$($mysql_cmd -N -e "SELECT DISTINCT User FROM mysql.user WHERE User != '';" 2>/dev/null)
        
        for user in $users; do
            read -p "Change password for MySQL user '$user'? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                read -sp "Enter new password for $user: " new_pass
                echo
                $mysql_cmd -e "ALTER USER '$user'@'localhost' IDENTIFIED BY '$new_pass';" 2>/dev/null || \
                $mysql_cmd -e "SET PASSWORD FOR '$user'@'localhost' = PASSWORD('$new_pass');" 2>/dev/null
                success "Password changed for $user"
            fi
        done
        
        $mysql_cmd -e "FLUSH PRIVILEGES;" 2>/dev/null
    fi
    
    # PostgreSQL
    if systemctl is-active postgresql &>/dev/null; then
        info "=== PostgreSQL Password Changes ==="
        
        local pg_users=$(sudo -u postgres psql -t -c "SELECT rolname FROM pg_roles WHERE rolcanlogin = true;" 2>/dev/null)
        
        for user in $pg_users; do
            user=$(echo "$user" | tr -d ' ')
            [ -z "$user" ] && continue
            
            read -p "Change password for PostgreSQL user '$user'? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                read -sp "Enter new password for $user: " new_pass
                echo
                sudo -u postgres psql -c "ALTER USER \"$user\" WITH PASSWORD '$new_pass';" 2>/dev/null
                success "Password changed for $user"
            fi
        done
    fi
    
    log_action "Changed database passwords"
}

#=============================================================================
# CHECK DATABASE CONNECTIONS
#=============================================================================
check_db_connections() {
    header "Checking Database Connections"
    
    # MySQL/MariaDB
    if systemctl is-active mysql &>/dev/null || systemctl is-active mariadb &>/dev/null; then
        info "=== MySQL/MariaDB Connections ==="
        mysql -e "SHOW PROCESSLIST;" 2>/dev/null || mysql -p -e "SHOW PROCESSLIST;" 2>/dev/null
        
        echo ""
        ss -tnp | grep :3306
    fi
    
    # PostgreSQL
    if systemctl is-active postgresql &>/dev/null; then
        info "=== PostgreSQL Connections ==="
        sudo -u postgres psql -c "SELECT pid, usename, client_addr, application_name, state FROM pg_stat_activity;" 2>/dev/null
        
        echo ""
        ss -tnp | grep :5432
    fi
}

#=============================================================================
# BACKUP DATABASE
#=============================================================================
backup_database() {
    header "Backup Database"
    
    local backup_dir="/tmp/db-backup-$(timestamp)"
    mkdir -p "$backup_dir"
    
    # MySQL/MariaDB
    if systemctl is-active mysql &>/dev/null || systemctl is-active mariadb &>/dev/null; then
        info "Backing up MySQL/MariaDB..."
        
        read -sp "Enter MySQL root password: " mysql_pass
        echo
        
        mysqldump -p"$mysql_pass" --all-databases > "$backup_dir/mysql-all.sql" 2>/dev/null
        
        if [ -f "$backup_dir/mysql-all.sql" ]; then
            success "MySQL backup: $backup_dir/mysql-all.sql"
        fi
    fi
    
    # PostgreSQL
    if systemctl is-active postgresql &>/dev/null; then
        info "Backing up PostgreSQL..."
        sudo -u postgres pg_dumpall > "$backup_dir/postgres-all.sql" 2>/dev/null
        
        if [ -f "$backup_dir/postgres-all.sql" ]; then
            success "PostgreSQL backup: $backup_dir/postgres-all.sql"
        fi
    fi
    
    # Create tarball
    tar -czf "${backup_dir}.tar.gz" -C /tmp "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    success "Database backup: ${backup_dir}.tar.gz"
    log_action "Created database backup"
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    detect_database
    
    echo ""
    echo "Database Hardening Options:"
    echo "1) Harden MySQL/MariaDB"
    echo "2) Harden PostgreSQL"
    echo "3) Audit database users"
    echo "4) Change database passwords"
    echo "5) Check active connections"
    echo "6) Backup databases"
    echo "7) Harden all detected databases"
    echo ""
    read -p "Select option [1-7]: " choice
    
    case $choice in
        1) harden_mysql ;;
        2) harden_postgresql ;;
        3) audit_db_users ;;
        4) change_db_passwords ;;
        5) check_db_connections ;;
        6) backup_database ;;
        7)
            for db in "${DATABASES[@]}"; do
                case "$db" in
                    mysql) harden_mysql ;;
                    postgresql) harden_postgresql ;;
                esac
            done
            ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
