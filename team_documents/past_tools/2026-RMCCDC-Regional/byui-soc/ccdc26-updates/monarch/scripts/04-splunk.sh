#!/bin/bash
# CCDC26 Monarch - Splunk Universal Forwarder Deployment
# Reads SPLUNK_SERVER and SPLUNK_PORT from environment (set via Monarch .env)
# SELF-CONTAINED -- no external dependencies

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; PURPLE='\033[0;35m'; NC='\033[0m'; BOLD='\033[1m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
phase() { echo -e "\n${BOLD}${PURPLE}[PHASE] $1${NC}\n"; }

if [ "$EUID" -ne 0 ]; then error "Must be run as root"; exit 1; fi

# Distro detection
DISTRO_FAMILY="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        ubuntu|debian|kali|mint|pop) DISTRO_FAMILY="debian" ;;
        rhel|centos|fedora|rocky|alma|oracle) DISTRO_FAMILY="rhel" ;;
        alpine) DISTRO_FAMILY="alpine" ;;
        arch|manjaro) DISTRO_FAMILY="arch" ;;
        opensuse*|sles) DISTRO_FAMILY="suse" ;;
    esac
fi

# Configuration from environment
SPLUNK_SERVER="${SPLUNK_SERVER:-}"
SPLUNK_PORT="${SPLUNK_PORT:-9997}"
SPLUNK_VERSION="${SPLUNK_VERSION:-9.4.1}"
SPLUNK_BUILD="${SPLUNK_BUILD:-e3bdab203ac8}"
SPLUNK_HOME="/opt/splunkforwarder"

if [ -z "$SPLUNK_SERVER" ]; then
    error "SPLUNK_SERVER not set in environment."
    error "Export it or set it in Monarch's .env file."
    exit 1
fi

SPLUNK_DEB_URL="https://download.splunk.com/products/universalforwarder/releases/${SPLUNK_VERSION}/linux/splunkforwarder-${SPLUNK_VERSION}-${SPLUNK_BUILD}-linux-amd64.deb"
SPLUNK_RPM_URL="https://download.splunk.com/products/universalforwarder/releases/${SPLUNK_VERSION}/linux/splunkforwarder-${SPLUNK_VERSION}-${SPLUNK_BUILD}.x86_64.rpm"
SPLUNK_TGZ_URL="https://download.splunk.com/products/universalforwarder/releases/${SPLUNK_VERSION}/linux/splunkforwarder-${SPLUNK_VERSION}-${SPLUNK_BUILD}-linux-amd64.tgz"

#=============================================================================
phase "Installing Splunk Universal Forwarder"
#=============================================================================

if [ -f "$SPLUNK_HOME/bin/splunk" ]; then
    info "Splunk UF already installed at $SPLUNK_HOME"
else
    TMP_DIR="/tmp/splunk_install_$$"
    mkdir -p "$TMP_DIR"

    download() {
        local url="$1" dest="$2"
        if command -v wget &>/dev/null; then
            wget -q "$url" -O "$dest"
        elif command -v curl &>/dev/null; then
            curl -sL "$url" -o "$dest"
        else
            error "No wget or curl available"
            return 1
        fi
    }

    case "$DISTRO_FAMILY" in
        debian)
            info "Downloading Splunk UF .deb..."
            if download "$SPLUNK_DEB_URL" "$TMP_DIR/splunkuf.deb"; then
                dpkg -i "$TMP_DIR/splunkuf.deb" 2>/dev/null
            else
                warn "DEB download failed, falling back to tarball"
                download "$SPLUNK_TGZ_URL" "$TMP_DIR/splunkuf.tgz" && \
                    tar -xzf "$TMP_DIR/splunkuf.tgz" -C /opt/
            fi
            ;;
        rhel)
            info "Downloading Splunk UF .rpm..."
            if download "$SPLUNK_RPM_URL" "$TMP_DIR/splunkuf.rpm"; then
                rpm -i "$TMP_DIR/splunkuf.rpm" 2>/dev/null
            else
                warn "RPM download failed, falling back to tarball"
                download "$SPLUNK_TGZ_URL" "$TMP_DIR/splunkuf.tgz" && \
                    tar -xzf "$TMP_DIR/splunkuf.tgz" -C /opt/
            fi
            ;;
        *)
            info "Downloading Splunk UF tarball..."
            download "$SPLUNK_TGZ_URL" "$TMP_DIR/splunkuf.tgz" && \
                tar -xzf "$TMP_DIR/splunkuf.tgz" -C /opt/
            ;;
    esac

    rm -rf "$TMP_DIR"

    if [ ! -f "$SPLUNK_HOME/bin/splunk" ]; then
        error "Splunk UF installation failed -- binary not found"
        exit 1
    fi
    ok "Splunk UF installed"
fi

#=============================================================================
phase "Configuring Outputs"
#=============================================================================

mkdir -p "$SPLUNK_HOME/etc/system/local"

cat > "$SPLUNK_HOME/etc/system/local/outputs.conf" << EOF
[tcpout]
defaultGroup = ccdc_splunk

[tcpout:ccdc_splunk]
server = ${SPLUNK_SERVER}:${SPLUNK_PORT}
compressed = true

[tcpout-server://${SPLUNK_SERVER}:${SPLUNK_PORT}]
EOF
ok "outputs.conf written (${SPLUNK_SERVER}:${SPLUNK_PORT})"

#=============================================================================
phase "Configuring Inputs"
#=============================================================================

cat > "$SPLUNK_HOME/etc/system/local/inputs.conf" << EOF
[default]
host = $(hostname)

# Security Logs
[monitor:///var/log/auth.log]
disabled = false
sourcetype = linux_secure
index = linux-security
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$

[monitor:///var/log/secure]
disabled = false
sourcetype = linux_secure
index = linux-security
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$

[monitor:///var/log/audit/audit.log]
disabled = false
sourcetype = linux_audit
index = linux-security
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$

[monitor:///var/log/fail2ban.log]
disabled = false
sourcetype = fail2ban
index = linux-security
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$

# System Logs
[monitor:///var/log/syslog]
disabled = false
sourcetype = syslog
index = linux-os
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$

[monitor:///var/log/messages]
disabled = false
sourcetype = syslog
index = linux-os
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$

[monitor:///var/log/kern.log]
disabled = false
sourcetype = linux_kernel
index = linux-os
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$

[monitor:///var/log/cron*]
disabled = false
sourcetype = cron
index = linux-os
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$

# Web Server Logs
[monitor:///var/log/apache2/*access*.log]
disabled = false
sourcetype = access_combined
index = linux-web
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$

[monitor:///var/log/apache2/*error*.log]
disabled = false
sourcetype = apache_error
index = linux-web
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$

[monitor:///var/log/httpd/*access*.log]
disabled = false
sourcetype = access_combined
index = linux-web
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$

[monitor:///var/log/httpd/*error*.log]
disabled = false
sourcetype = apache_error
index = linux-web
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$

[monitor:///var/log/nginx/access.log]
disabled = false
sourcetype = access_combined
index = linux-web
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$

[monitor:///var/log/nginx/error.log]
disabled = false
sourcetype = nginx_error
index = linux-web
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$

# Database Logs
[monitor:///var/log/mysql/*.log]
disabled = false
sourcetype = mysql_error
index = linux-database
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$

[monitor:///var/log/mariadb/*.log]
disabled = false
sourcetype = mysql_error
index = linux-database
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$

[monitor:///var/log/postgresql/*.log]
disabled = false
sourcetype = postgresql
index = linux-database
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$

# Mail Logs
[monitor:///var/log/mail.log]
disabled = false
sourcetype = sendmail
index = linux-mail
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$

[monitor:///var/log/maillog]
disabled = false
sourcetype = sendmail
index = linux-mail
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$

# DNS Logs
[monitor:///var/log/named/*.log]
disabled = false
sourcetype = named
index = linux-dns
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$

[monitor:///var/log/bind/*.log]
disabled = false
sourcetype = named
index = linux-dns
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$

# FTP Logs
[monitor:///var/log/vsftpd.log]
disabled = false
sourcetype = vsftpd
index = linux-ftp
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$

[monitor:///var/log/proftpd/*.log]
disabled = false
sourcetype = proftpd
index = linux-ftp
blacklist = \\.(gz|bz2|xz|zip)$|\\.\\d$
EOF

chown -R root:root "$SPLUNK_HOME/etc/system/local"
chmod 600 "$SPLUNK_HOME/etc/system/local"/*.conf
ok "inputs.conf written with all log sources"

#=============================================================================
phase "Starting Splunk Forwarder"
#=============================================================================

"$SPLUNK_HOME/bin/splunk" start --accept-license --answer-yes --no-prompt 2>/dev/null
"$SPLUNK_HOME/bin/splunk" enable boot-start -systemd-managed 1 2>/dev/null || \
    "$SPLUNK_HOME/bin/splunk" enable boot-start 2>/dev/null

ok "Splunk forwarder started and enabled at boot"

#=============================================================================
phase "Verification"
#=============================================================================

if "$SPLUNK_HOME/bin/splunk" status 2>/dev/null | grep -q "running"; then
    ok "Splunk forwarder is running"
else
    warn "Splunk forwarder may not be running -- check manually"
fi

info "Target: ${SPLUNK_SERVER}:${SPLUNK_PORT}"

echo ""
ok "Splunk UF deployment complete"
