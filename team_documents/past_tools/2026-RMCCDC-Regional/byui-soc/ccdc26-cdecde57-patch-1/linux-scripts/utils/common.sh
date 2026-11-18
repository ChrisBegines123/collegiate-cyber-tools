#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Common Utilities
# Source this file in other scripts: source "$(dirname "$0")/../utils/common.sh"

#=============================================================================
# COLORS AND OUTPUT
#=============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
header()  { echo -e "\n${BOLD}${PURPLE}=== $1 ===${NC}\n"; }
finding() { echo -e "${RED}[FINDING]${NC} $1"; }

#=============================================================================
# DISTRIBUTION DETECTION
#=============================================================================
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="$ID"
        DISTRO_FAMILY=""
        
        case "$ID" in
            ubuntu|debian|kali|mint|pop)
                DISTRO_FAMILY="debian"
                PKG_MGR="apt"
                ;;
            rhel|centos|fedora|rocky|alma|oracle)
                DISTRO_FAMILY="rhel"
                if command -v dnf &>/dev/null; then
                    PKG_MGR="dnf"
                else
                    PKG_MGR="yum"
                fi
                ;;
            alpine)
                DISTRO_FAMILY="alpine"
                PKG_MGR="apk"
                ;;
            arch|manjaro|endeavouros)
                DISTRO_FAMILY="arch"
                PKG_MGR="pacman"
                ;;
            opensuse*|sles)
                DISTRO_FAMILY="suse"
                PKG_MGR="zypper"
                ;;
            *)
                DISTRO_FAMILY="unknown"
                PKG_MGR="unknown"
                ;;
        esac
    else
        DISTRO_ID="unknown"
        DISTRO_FAMILY="unknown"
        PKG_MGR="unknown"
    fi
    
    export DISTRO_ID DISTRO_FAMILY PKG_MGR
}

#=============================================================================
# INIT SYSTEM DETECTION
#=============================================================================
detect_init() {
    if [ -d /run/systemd/system ]; then
        INIT_SYSTEM="systemd"
    elif [ -f /sbin/openrc ]; then
        INIT_SYSTEM="openrc"
    elif [ -f /etc/init.d/cron ]; then
        INIT_SYSTEM="sysvinit"
    else
        INIT_SYSTEM="unknown"
    fi
    export INIT_SYSTEM
}

#=============================================================================
# ROOT CHECK
#=============================================================================
require_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root"
        exit 1
    fi
}

#=============================================================================
# BACKUP FUNCTION
#=============================================================================
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local backup="${file}.bak.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup"
        info "Backed up $file to $backup"
    fi
}

#=============================================================================
# LOGGING
#=============================================================================
LOG_DIR="/var/log/ccdc-toolkit"
mkdir -p "$LOG_DIR" 2>/dev/null

log_action() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_DIR/actions.log"
}

log_finding() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_DIR/findings.log"
    finding "$msg"
}

#=============================================================================
# SERVICE MANAGEMENT (Cross-distro)
#=============================================================================
service_stop() {
    local service="$1"
    case "$INIT_SYSTEM" in
        systemd)
            systemctl stop "$service" 2>/dev/null
            systemctl disable "$service" 2>/dev/null
            ;;
        openrc)
            rc-service "$service" stop 2>/dev/null
            rc-update del "$service" 2>/dev/null
            ;;
        sysvinit)
            service "$service" stop 2>/dev/null
            update-rc.d "$service" disable 2>/dev/null
            ;;
    esac
}

service_start() {
    local service="$1"
    case "$INIT_SYSTEM" in
        systemd)
            systemctl enable "$service" 2>/dev/null
            systemctl start "$service" 2>/dev/null
            ;;
        openrc)
            rc-update add "$service" 2>/dev/null
            rc-service "$service" start 2>/dev/null
            ;;
        sysvinit)
            update-rc.d "$service" enable 2>/dev/null
            service "$service" start 2>/dev/null
            ;;
    esac
}

service_status() {
    local service="$1"
    case "$INIT_SYSTEM" in
        systemd)
            systemctl is-active "$service" 2>/dev/null
            ;;
        openrc)
            rc-service "$service" status 2>/dev/null
            ;;
        sysvinit)
            service "$service" status 2>/dev/null
            ;;
    esac
}

#=============================================================================
# FIREWALL MANAGEMENT (Cross-distro)
#=============================================================================
detect_firewall() {
    if command -v ufw &>/dev/null && ufw status &>/dev/null; then
        FIREWALL="ufw"
    elif command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
        FIREWALL="firewalld"
    elif command -v iptables &>/dev/null; then
        FIREWALL="iptables"
    elif command -v nft &>/dev/null; then
        FIREWALL="nftables"
    else
        FIREWALL="none"
    fi
    export FIREWALL
}

#=============================================================================
# PACKAGE MANAGEMENT (Cross-distro)
#=============================================================================
pkg_install() {
    local pkg="$1"
    case "$PKG_MGR" in
        apt)
            apt-get install -y "$pkg" 2>/dev/null
            ;;
        dnf|yum)
            $PKG_MGR install -y "$pkg" 2>/dev/null
            ;;
        apk)
            apk add "$pkg" 2>/dev/null
            ;;
        pacman)
            pacman -S --noconfirm "$pkg" 2>/dev/null
            ;;
        zypper)
            zypper install -y "$pkg" 2>/dev/null
            ;;
    esac
}

pkg_remove() {
    local pkg="$1"
    case "$PKG_MGR" in
        apt)
            apt-get remove -y "$pkg" 2>/dev/null
            ;;
        dnf|yum)
            $PKG_MGR remove -y "$pkg" 2>/dev/null
            ;;
        apk)
            apk del "$pkg" 2>/dev/null
            ;;
        pacman)
            pacman -R --noconfirm "$pkg" 2>/dev/null
            ;;
        zypper)
            zypper remove -y "$pkg" 2>/dev/null
            ;;
    esac
}

#=============================================================================
# USER MANAGEMENT
#=============================================================================
generate_password() {
    # Generate a strong random password
    local length="${1:-16}"
    tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c "$length"
    echo
}

get_human_users() {
    # Get list of human users (UID >= 1000 or root)
    awk -F: '($3 >= 1000 && $3 < 65534) || $3 == 0 {print $1}' /etc/passwd
}

get_sudo_users() {
    # Get users with sudo privileges
    local sudo_users=()
    
    # Check sudoers file
    if [ -f /etc/sudoers ]; then
        grep -E '^[^#]*ALL.*ALL' /etc/sudoers 2>/dev/null | awk '{print $1}' | grep -v '%'
    fi
    
    # Check sudoers.d
    if [ -d /etc/sudoers.d ]; then
        grep -rE '^[^#]*ALL.*ALL' /etc/sudoers.d/ 2>/dev/null | awk -F: '{print $2}' | awk '{print $1}' | grep -v '%'
    fi
    
    # Check sudo/wheel group members
    getent group sudo 2>/dev/null | cut -d: -f4 | tr ',' '\n'
    getent group wheel 2>/dev/null | cut -d: -f4 | tr ',' '\n'
}

#=============================================================================
# NETWORK UTILITIES
#=============================================================================
get_listening_ports() {
    if command -v ss &>/dev/null; then
        ss -tlnp 2>/dev/null
    elif command -v netstat &>/dev/null; then
        netstat -tlnp 2>/dev/null
    fi
}

get_established_connections() {
    if command -v ss &>/dev/null; then
        ss -tnp state established 2>/dev/null
    elif command -v netstat &>/dev/null; then
        netstat -tnp 2>/dev/null | grep ESTABLISHED
    fi
}

#=============================================================================
# HASH UTILITIES
#=============================================================================
hash_file() {
    local file="$1"
    if command -v sha256sum &>/dev/null; then
        sha256sum "$file" 2>/dev/null | awk '{print $1}'
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$file" 2>/dev/null | awk '{print $1}'
    fi
}

#=============================================================================
# TIMESTAMP
#=============================================================================
timestamp() {
    date '+%Y%m%d_%H%M%S'
}

#=============================================================================
# INITIALIZE
#=============================================================================
detect_distro
detect_init
detect_firewall

# Export toolkit directory
TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TOOLKIT_DIR
