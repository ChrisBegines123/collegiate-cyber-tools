#!/bin/bash
# CCDC26 Monarch - Firewall Configuration
# Auto-detect running services, apply rules, anti-lockout safety
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
DISTRO_FAMILY="unknown"; PKG_MGR="unknown"; INIT_SYSTEM="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        ubuntu|debian|kali|mint|pop) DISTRO_FAMILY="debian"; PKG_MGR="apt" ;;
        rhel|centos|fedora|rocky|alma|oracle)
            DISTRO_FAMILY="rhel"
            command -v dnf &>/dev/null && PKG_MGR="dnf" || PKG_MGR="yum"
            ;;
        alpine) DISTRO_FAMILY="alpine"; PKG_MGR="apk" ;;
        arch|manjaro) DISTRO_FAMILY="arch"; PKG_MGR="pacman" ;;
        opensuse*|sles) DISTRO_FAMILY="suse"; PKG_MGR="zypper" ;;
    esac
fi
[ -d /run/systemd/system ] && INIT_SYSTEM="systemd"

#=============================================================================
phase "Detecting Running Services"
#=============================================================================

DETECTED_TCP="22"
DETECTED_UDP=""

check_service() {
    local name="$1"
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl is-active "$name" &>/dev/null && return 0
    fi
    pgrep -x "$name" &>/dev/null && return 0
    return 1
}

if check_service apache2 || check_service httpd || check_service nginx; then
    DETECTED_TCP="$DETECTED_TCP 80 443"
    info "Detected: Web server (HTTP/HTTPS)"
fi

if check_service postfix || check_service sendmail || pgrep -x master &>/dev/null; then
    DETECTED_TCP="$DETECTED_TCP 25 587"
    info "Detected: SMTP"
fi

if check_service dovecot; then
    DETECTED_TCP="$DETECTED_TCP 110 143 993 995"
    info "Detected: IMAP/POP3"
fi

if check_service named || check_service bind9; then
    DETECTED_TCP="$DETECTED_TCP 53"
    DETECTED_UDP="$DETECTED_UDP 53"
    info "Detected: DNS"
fi

if check_service vsftpd || check_service proftpd; then
    DETECTED_TCP="$DETECTED_TCP 20 21"
    info "Detected: FTP"
fi

if check_service mysql || check_service mariadb; then
    DETECTED_TCP="$DETECTED_TCP 3306"
    info "Detected: MySQL/MariaDB"
fi

if check_service postgresql; then
    DETECTED_TCP="$DETECTED_TCP 5432"
    info "Detected: PostgreSQL"
fi

if pgrep -f splunkd &>/dev/null || check_service splunk; then
    DETECTED_TCP="$DETECTED_TCP 8000 8089 9997"
    info "Detected: Splunk"
fi

if check_service smbd; then
    DETECTED_TCP="$DETECTED_TCP 139 445"
    info "Detected: Samba"
fi

if check_service slapd; then
    DETECTED_TCP="$DETECTED_TCP 389 636"
    info "Detected: LDAP"
fi

# Deduplicate
ALLOWED_TCP=$(echo "$DETECTED_TCP" | tr ' ' '\n' | sort -un | tr '\n' ' ')
ALLOWED_UDP=$(echo "$DETECTED_UDP" | tr ' ' '\n' | sort -un | tr '\n' ' ')

echo ""
info "Allowed TCP ports: $ALLOWED_TCP"
info "Allowed UDP ports: ${ALLOWED_UDP:-none}"

#=============================================================================
phase "Configuring Firewall"
#=============================================================================

# Determine firewall backend
FW_BACKEND="iptables"
if command -v ufw &>/dev/null; then
    FW_BACKEND="ufw"
elif command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null 2>&1; then
    FW_BACKEND="firewalld"
fi

info "Using firewall backend: $FW_BACKEND"

configure_ufw() {
    command -v ufw &>/dev/null || { apt-get update -qq && apt-get install -y -qq ufw; }
    ufw --force reset >/dev/null
    ufw default deny incoming
    ufw default allow outgoing
    for port in $ALLOWED_TCP; do
        ufw allow "$port/tcp" >/dev/null
    done
    for port in $ALLOWED_UDP; do
        ufw allow "$port/udp" >/dev/null
    done
    ufw logging on >/dev/null
    ufw logging high >/dev/null
    ufw --force enable >/dev/null
    ok "UFW configured"
    ufw status verbose
}

configure_firewalld() {
    systemctl start firewalld 2>/dev/null
    firewall-cmd --set-default-zone=drop 2>/dev/null
    for svc in $(firewall-cmd --list-services 2>/dev/null); do
        firewall-cmd --permanent --remove-service="$svc" 2>/dev/null
    done
    for port in $ALLOWED_TCP; do
        firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null
    done
    for port in $ALLOWED_UDP; do
        firewall-cmd --permanent --add-port="${port}/udp" >/dev/null
    done
    firewall-cmd --permanent --set-log-denied=all 2>/dev/null
    firewall-cmd --reload >/dev/null
    ok "Firewalld configured"
    firewall-cmd --list-all
}

configure_iptables() {
    info "Backing up current rules..."
    iptables-save > "/root/iptables-backup-$(date +%Y%m%d_%H%M%S).rules" 2>/dev/null

    iptables -F; iptables -X
    iptables -t nat -F; iptables -t nat -X
    iptables -t mangle -F; iptables -t mangle -X

    # Create logging chains
    iptables -N INPUT_DROP 2>/dev/null || iptables -F INPUT_DROP
    iptables -A INPUT_DROP -j LOG --log-prefix "IPTABLES_DROP: " --log-level 4
    iptables -A INPUT_DROP -j DROP

    iptables -N INPUT_ACCEPT 2>/dev/null || iptables -F INPUT_ACCEPT
    iptables -A INPUT_ACCEPT -j LOG --log-prefix "IPTABLES_ACCEPT: " --log-level 6
    iptables -A INPUT_ACCEPT -j ACCEPT

    # Default policies
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    # Loopback
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT

    # Established/related
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # TCP ports
    for port in $ALLOWED_TCP; do
        iptables -A INPUT -p tcp --dport "$port" -j INPUT_ACCEPT
    done

    # UDP ports
    for port in $ALLOWED_UDP; do
        iptables -A INPUT -p udp --dport "$port" -j INPUT_ACCEPT
    done

    # ICMP
    iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

    # Drop everything else through logging chain
    iptables -A INPUT -j INPUT_DROP

    ok "iptables configured"
    iptables -L -n -v --line-numbers

    # Persist rules
    info "Persisting rules..."
    case "$DISTRO_FAMILY" in
        debian)
            if command -v netfilter-persistent &>/dev/null; then
                netfilter-persistent save 2>/dev/null
            else
                iptables-save > /etc/iptables.rules
                mkdir -p /etc/network/if-pre-up.d
                cat > /etc/network/if-pre-up.d/iptables << 'IPTEOF'
#!/bin/sh
iptables-restore < /etc/iptables.rules
IPTEOF
                chmod +x /etc/network/if-pre-up.d/iptables
            fi
            ;;
        rhel)
            service iptables save 2>/dev/null || iptables-save > /etc/sysconfig/iptables
            ;;
        alpine)
            iptables-save > /etc/iptables/rules-save 2>/dev/null
            ;;
    esac
}

#=============================================================================
phase "Anti-Lockout Safety Check"
#=============================================================================

info "Applying firewall rules..."
info "Testing SSH connectivity after apply (3s grace)..."

# Save current rules for rollback
ROLLBACK="/tmp/iptables-rollback-$$.rules"
iptables-save > "$ROLLBACK" 2>/dev/null

case "$FW_BACKEND" in
    ufw)       configure_ufw ;;
    firewalld) configure_firewalld ;;
    *)         configure_iptables ;;
esac

# Anti-lockout: verify SSH port is open
sleep 1
SSH_CHECK=false
if command -v ss &>/dev/null; then
    ss -tlnp 2>/dev/null | grep -q ":22 " && SSH_CHECK=true
elif command -v netstat &>/dev/null; then
    netstat -tlnp 2>/dev/null | grep -q ":22 " && SSH_CHECK=true
fi

if ! $SSH_CHECK; then
    error "SSH port 22 not detected as listening! Rolling back..."
    iptables-restore < "$ROLLBACK" 2>/dev/null
    error "Firewall rolled back to previous state"
else
    ok "SSH port 22 is listening -- firewall rules confirmed safe"
fi

rm -f "$ROLLBACK"

echo ""
ok "Firewall configuration complete"
echo ""
echo "Allowed TCP: $ALLOWED_TCP"
echo "Allowed UDP: ${ALLOWED_UDP:-none}"
echo "Backend: $FW_BACKEND"
