#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - FTP Server Hardening
# Secure vsftpd, ProFTPD, and Pure-FTPd

source "$(dirname "$0")/../utils/common.sh"
require_root

header "FTP Server Hardening"

#=============================================================================
# DETECT FTP SERVER
#=============================================================================
detect_ftp_server() {
    FTP_SERVER="none"
    
    if systemctl is-active vsftpd &>/dev/null; then
        FTP_SERVER="vsftpd"
    elif systemctl is-active proftpd &>/dev/null; then
        FTP_SERVER="proftpd"
    elif systemctl is-active pure-ftpd &>/dev/null; then
        FTP_SERVER="pure-ftpd"
    fi
    
    if [ "$FTP_SERVER" == "none" ]; then
        warn "No running FTP server detected"
        return 1
    fi
    
    info "Detected FTP server: $FTP_SERVER"
    return 0
}

#=============================================================================
# HARDEN VSFTPD
#=============================================================================
harden_vsftpd() {
    header "Hardening vsftpd"
    
    local vsftpd_conf="/etc/vsftpd.conf"
    [ ! -f "$vsftpd_conf" ] && vsftpd_conf="/etc/vsftpd/vsftpd.conf"
    
    if [ ! -f "$vsftpd_conf" ]; then
        error "vsftpd configuration not found"
        return 1
    fi
    
    backup_file "$vsftpd_conf"
    
    cat > "$vsftpd_conf" << 'EOF'
# CCDC26 vsftpd Secure Configuration

# Standalone mode
listen=YES
listen_ipv6=NO

# Access control
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022

# Security
chroot_local_user=YES
allow_writeable_chroot=YES
secure_chroot_dir=/var/run/vsftpd/empty

# Hide user info
hide_ids=YES

# Disable dangerous commands
chmod_enable=NO

# Logging
xferlog_enable=YES
xferlog_std_format=YES
xferlog_file=/var/log/vsftpd.log
log_ftp_protocol=YES
dual_log_enable=YES
vsftpd_log_file=/var/log/vsftpd.log

# Connection settings
idle_session_timeout=300
data_connection_timeout=120
max_clients=50
max_per_ip=5

# Passive mode (adjust ports as needed)
pasv_enable=YES
pasv_min_port=30000
pasv_max_port=31000

# SSL/TLS (recommended)
ssl_enable=NO
# Uncomment below if you have certificates:
# ssl_enable=YES
# rsa_cert_file=/etc/ssl/certs/vsftpd.pem
# rsa_private_key_file=/etc/ssl/private/vsftpd.key
# ssl_tlsv1=YES
# ssl_sslv2=NO
# ssl_sslv3=NO
# force_local_data_ssl=YES
# force_local_logins_ssl=YES

# PAM authentication
pam_service_name=vsftpd

# User list (deny users in list)
userlist_enable=YES
userlist_deny=YES
userlist_file=/etc/vsftpd.userlist

# Banner
ftpd_banner=FTP Server Ready

# Restrict to local users only
local_root=/home/$USER
EOF

    # Create userlist (users to deny)
    cat > /etc/vsftpd.userlist << 'EOF'
root
daemon
bin
sys
sync
games
man
lp
mail
news
uucp
proxy
www-data
backup
list
irc
gnats
nobody
systemd-network
systemd-resolve
syslog
messagebus
_apt
uuidd
EOF

    # Test and restart
    if vsftpd -olisten=NO /dev/null 2>/dev/null; then
        systemctl restart vsftpd
        success "vsftpd restarted"
    else
        error "vsftpd configuration error"
    fi
    
    log_action "Hardened vsftpd"
}

#=============================================================================
# HARDEN PROFTPD
#=============================================================================
harden_proftpd() {
    header "Hardening ProFTPD"
    
    local proftpd_conf="/etc/proftpd/proftpd.conf"
    [ ! -f "$proftpd_conf" ] && proftpd_conf="/etc/proftpd.conf"
    
    if [ ! -f "$proftpd_conf" ]; then
        error "ProFTPD configuration not found"
        return 1
    fi
    
    backup_file "$proftpd_conf"
    
    cat > "$proftpd_conf" << 'EOF'
# CCDC26 ProFTPD Secure Configuration

ServerName "FTP Server"
ServerType standalone
DefaultServer on

# Security
ServerIdent off
DeferWelcome on
UseReverseDNS off
IdentLookups off

# Disable root login
RootLogin off

# Chroot users
DefaultRoot ~

# Umask
Umask 022 022

# Logging
SystemLog /var/log/proftpd/proftpd.log
TransferLog /var/log/proftpd/xferlog

# Limits
MaxInstances 30
MaxClients 50
MaxClientsPerHost 5
MaxLoginAttempts 3
TimeoutIdle 300
TimeoutNoTransfer 300
TimeoutStalled 300
TimeoutLogin 30

# Passive ports
PassivePorts 30000 31000

# Disable dangerous commands
<Limit SITE_CHMOD>
  DenyAll
</Limit>

# Deny anonymous
<Anonymous ~ftp>
  User ftp
  Group nogroup
  RequireValidShell off
  DenyAll
</Anonymous>

# User restrictions
<Global>
  AllowOverwrite on
  <Limit ALL SITE_CHMOD>
    AllowUser !root
  </Limit>
</Global>
EOF

    # Test and restart
    if proftpd -t 2>/dev/null; then
        systemctl restart proftpd
        success "ProFTPD restarted"
    else
        error "ProFTPD configuration error"
        proftpd -t
    fi
    
    log_action "Hardened ProFTPD"
}

#=============================================================================
# HARDEN PURE-FTPD
#=============================================================================
harden_pureftpd() {
    header "Hardening Pure-FTPd"
    
    local conf_dir="/etc/pure-ftpd/conf"
    
    if [ ! -d "$conf_dir" ]; then
        # Debian/Ubuntu style
        mkdir -p "$conf_dir"
    fi
    
    # Configure via files
    echo "yes" > "$conf_dir/ChrootEveryone"
    echo "yes" > "$conf_dir/NoAnonymous"
    echo "yes" > "$conf_dir/ProhibitDotFilesWrite"
    echo "yes" > "$conf_dir/ProhibitDotFilesRead"
    echo "no" > "$conf_dir/AnonymousOnly"
    echo "no" > "$conf_dir/AnonymousCantUpload"
    echo "50" > "$conf_dir/MaxClientsNumber"
    echo "5" > "$conf_dir/MaxClientsPerIP"
    echo "15" > "$conf_dir/MaxIdleTime"
    echo "yes" > "$conf_dir/NoChmod"
    echo "30000 31000" > "$conf_dir/PassivePortRange"
    echo "2" > "$conf_dir/MinUID"
    echo "/var/log/pure-ftpd/transfer.log" > "$conf_dir/AltLog"
    
    # Restart
    systemctl restart pure-ftpd 2>/dev/null || systemctl restart pure-ftpd-mysql 2>/dev/null
    success "Pure-FTPd restarted"
    
    log_action "Hardened Pure-FTPd"
}

#=============================================================================
# CHECK FTP SECURITY
#=============================================================================
check_ftp_security() {
    header "Checking FTP Security"
    
    # Check if anonymous is enabled
    info "=== Anonymous Access Check ==="
    
    if [ -f /etc/vsftpd.conf ] || [ -f /etc/vsftpd/vsftpd.conf ]; then
        local anon=$(grep -h "anonymous_enable" /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf 2>/dev/null | grep -v "^#" | tail -1)
        if echo "$anon" | grep -qi "yes"; then
            log_finding "vsftpd: Anonymous access ENABLED"
        else
            success "vsftpd: Anonymous access disabled"
        fi
    fi
    
    # Check listening
    info "=== FTP Ports ==="
    ss -tlnp | grep -E ':(21|20|990) '
    
    # Check for plaintext passwords
    info "=== Checking for plaintext password transmission ==="
    if [ "$FTP_SERVER" == "vsftpd" ]; then
        local ssl=$(grep -h "ssl_enable" /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf 2>/dev/null | grep -v "^#" | tail -1)
        if echo "$ssl" | grep -qi "yes"; then
            success "SSL/TLS is enabled"
        else
            warn "SSL/TLS is NOT enabled - passwords sent in plaintext!"
        fi
    fi
    
    # Check for world-writable FTP directories
    info "=== Checking FTP directories ==="
    for dir in /srv/ftp /var/ftp /home/ftp; do
        if [ -d "$dir" ]; then
            local perms=$(stat -c %a "$dir")
            echo "$dir: $perms"
            if [ "${perms: -1}" -ge 2 ]; then
                log_finding "World-writable FTP directory: $dir"
            fi
        fi
    done
    
    # Recent connections
    info "=== Recent FTP Activity ==="
    for log in /var/log/vsftpd.log /var/log/proftpd/proftpd.log /var/log/pure-ftpd/transfer.log; do
        if [ -f "$log" ]; then
            echo "=== $log ==="
            tail -20 "$log"
        fi
    done
}

#=============================================================================
# AUDIT FTP USERS
#=============================================================================
audit_ftp_users() {
    header "Auditing FTP Users"
    
    # Users with FTP shells
    info "=== Users with FTP access ==="
    
    # Check for users with valid shells
    while IFS=: read -r username _ uid gid _ home shell; do
        # Skip system users
        [ "$uid" -lt 1000 ] && [ "$uid" -ne 0 ] && continue
        
        # Check if user can FTP
        if [ -n "$shell" ] && [ "$shell" != "/usr/sbin/nologin" ] && [ "$shell" != "/bin/false" ]; then
            echo "$username (UID: $uid, Home: $home, Shell: $shell)"
        fi
    done < /etc/passwd
    
    # Check vsftpd userlist
    if [ -f /etc/vsftpd.userlist ]; then
        echo ""
        info "=== vsftpd User List (denied users) ==="
        cat /etc/vsftpd.userlist
    fi
    
    # Check ftpusers (usually denied)
    if [ -f /etc/ftpusers ]; then
        echo ""
        info "=== /etc/ftpusers (denied users) ==="
        cat /etc/ftpusers
    fi
}

#=============================================================================
# DISABLE FTP (Replace with SFTP)
#=============================================================================
disable_ftp() {
    header "Disabling FTP Service"
    
    warn "This will stop and disable the FTP service"
    warn "Consider using SFTP (SSH File Transfer) instead"
    
    read -p "Disable FTP? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    for service in vsftpd proftpd pure-ftpd; do
        if systemctl is-active "$service" &>/dev/null; then
            systemctl stop "$service"
            systemctl disable "$service"
            success "Disabled $service"
        fi
    done
    
    info "SFTP is available via SSH by default"
    info "Users can connect with: sftp user@hostname"
    
    log_action "Disabled FTP services"
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    detect_ftp_server
    
    echo ""
    echo "FTP Hardening Options:"
    echo "1) Harden vsftpd"
    echo "2) Harden ProFTPD"
    echo "3) Harden Pure-FTPd"
    echo "4) Check FTP security"
    echo "5) Audit FTP users"
    echo "6) Disable FTP (use SFTP instead)"
    echo "7) Auto-harden detected server ($FTP_SERVER)"
    echo ""
    read -p "Select option [1-7]: " choice
    
    case $choice in
        1) harden_vsftpd ;;
        2) harden_proftpd ;;
        3) harden_pureftpd ;;
        4) check_ftp_security ;;
        5) audit_ftp_users ;;
        6) disable_ftp ;;
        7)
            case "$FTP_SERVER" in
                vsftpd) harden_vsftpd ;;
                proftpd) harden_proftpd ;;
                pure-ftpd) harden_pureftpd ;;
                *) error "No FTP server detected" ;;
            esac
            ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
