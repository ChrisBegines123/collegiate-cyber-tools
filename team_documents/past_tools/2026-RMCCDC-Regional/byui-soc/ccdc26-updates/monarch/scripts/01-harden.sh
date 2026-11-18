#!/bin/bash
# CCDC26 Monarch - Monolith System Hardening
# Runs top-to-bottom with NO interactive prompts. SELF-CONTAINED.
# Combines: distro detection, user audit, SSH, kernel, permissions, services
# NOTE: Does NOT change passwords -- Monarch handles that via SSH.

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
[ -f /sbin/openrc ] && INIT_SYSTEM="openrc"

svc_stop() {
    local s="$1"
    case "$INIT_SYSTEM" in
        systemd)  systemctl stop "$s" 2>/dev/null; systemctl disable "$s" 2>/dev/null ;;
        openrc)   rc-service "$s" stop 2>/dev/null; rc-update del "$s" 2>/dev/null ;;
        *)        service "$s" stop 2>/dev/null ;;
    esac
}

svc_restart() {
    local s="$1"
    case "$INIT_SYSTEM" in
        systemd)  systemctl restart "$s" 2>/dev/null ;;
        openrc)   rc-service "$s" restart 2>/dev/null ;;
        *)        service "$s" restart 2>/dev/null ;;
    esac
}

START_TIME=$(date +%s)
echo ""
echo -e "${BOLD}${GREEN}CCDC26 Monarch - Full System Hardening${NC}"
echo -e "${BOLD}Host: $(hostname) | $(date) | $DISTRO_FAMILY / $PKG_MGR / $INIT_SYSTEM${NC}"
echo ""

#=============================================================================
phase "1 - User Account Audit"
#=============================================================================

info "Checking for non-root UID 0 accounts..."
while IFS=: read -r username _ uid _; do
    if [ "$uid" -eq 0 ] && [ "$username" != "root" ]; then
        warn "UID 0 user (not root): $username"
    fi
done < /etc/passwd

info "Checking for users with empty passwords..."
while IFS=: read -r username password _; do
    if [ -z "$password" ]; then
        warn "Empty password hash: $username -- locking"
        passwd -l "$username" 2>/dev/null
    fi
done < /etc/shadow 2>/dev/null

info "Checking service accounts with login shells..."
while IFS=: read -r username _ uid _ _ _ shell; do
    if [ "$uid" -lt 1000 ] && [ "$uid" -ne 0 ]; then
        if [ "$shell" != "/usr/sbin/nologin" ] && [ "$shell" != "/bin/false" ] && \
           [ "$shell" != "/sbin/nologin" ] && [ -n "$shell" ]; then
            warn "Service account with shell: $username ($shell)"
        fi
    fi
done < /etc/passwd

ok "User audit complete"

#=============================================================================
phase "2 - Sudo Hardening"
#=============================================================================

backup_file /etc/sudoers

info "Installing secure sudo defaults..."
mkdir -p /etc/sudoers.d
cat > /etc/sudoers.d/ccdc-hardening << 'SUDOEOF'
Defaults    env_reset
Defaults    mail_badpass
Defaults    secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Defaults    logfile="/var/log/sudo.log"
Defaults    log_input,log_output
Defaults    passwd_tries=3
Defaults    passwd_timeout=1
Defaults    timestamp_timeout=5
SUDOEOF
chmod 440 /etc/sudoers.d/ccdc-hardening

if visudo -c &>/dev/null; then
    ok "Sudoers configuration valid"
else
    error "Sudoers configuration invalid! Restoring backup..."
    rm -f /etc/sudoers.d/ccdc-hardening
fi

#=============================================================================
phase "3 - Create Competition User"
#=============================================================================

COMP_USER="${COMP_USER:-sysadmin}"

if ! id "$COMP_USER" &>/dev/null; then
    info "Creating sudo user: $COMP_USER"
    useradd -m -s /bin/bash "$COMP_USER" 2>/dev/null || useradd -m "$COMP_USER" 2>/dev/null
    echo "$COMP_USER:changeme" | chpasswd 2>/dev/null
    ok "User $COMP_USER created (password: changeme -- rotate ASAP)"
else
    info "User $COMP_USER already exists"
fi

# Add to sudo/wheel group
if getent group sudo &>/dev/null; then
    usermod -aG sudo "$COMP_USER" 2>/dev/null
    ok "$COMP_USER added to sudo group"
elif getent group wheel &>/dev/null; then
    usermod -aG wheel "$COMP_USER" 2>/dev/null
    ok "$COMP_USER added to wheel group"
fi

# Ensure sudo works for the user
if ! grep -q "^${COMP_USER}" /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
    echo "${COMP_USER} ALL=(ALL) ALL" > /etc/sudoers.d/ccdc-comp-user
    chmod 440 /etc/sudoers.d/ccdc-comp-user
    ok "$COMP_USER granted sudo via sudoers.d"
fi

#=============================================================================
phase "4 - SSH Hardening"
#=============================================================================

SSHD_CONFIG="/etc/ssh/sshd_config"
backup_file "$SSHD_CONFIG"

info "Writing hardened SSH configuration..."
cat > "$SSHD_CONFIG" << 'SSHEOF'
# CCDC26 Hardened SSH - Monarch
Port 22
AddressFamily inet
ListenAddress 0.0.0.0
Protocol 2

PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

StrictModes yes
MaxAuthTries 3
MaxSessions 10
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2

X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no
PermitUserEnvironment no

SyslogFacility AUTH
LogLevel VERBOSE

Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group14-sha256

Banner /etc/ssh/banner
Subsystem sftp /usr/lib/openssh/sftp-server -f AUTHPRIV -l INFO
SSHEOF

cat > /etc/ssh/banner << 'BANEOF'
========================================================================
                      AUTHORIZED ACCESS ONLY
  All activities are monitored and logged. Unauthorized access will be
  reported and prosecuted to the fullest extent of the law.
========================================================================
BANEOF

if sshd -t 2>/dev/null; then
    svc_restart sshd 2>/dev/null || svc_restart ssh 2>/dev/null
    ok "SSH hardened and restarted"
else
    error "SSH config validation failed -- check manually"
fi

#=============================================================================
phase "5 - Kernel / Sysctl Hardening"
#=============================================================================

backup_file /etc/sysctl.conf

cat > /etc/sysctl.d/99-ccdc-hardening.conf << 'SYSEOF'
# CCDC26 Kernel Hardening
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.log_martians = 1
fs.suid_dumpable = 0
kernel.randomize_va_space = 2
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.perf_event_paranoid = 3
fs.protected_symlinks = 1
fs.protected_hardlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
SYSEOF

sysctl -p /etc/sysctl.d/99-ccdc-hardening.conf 2>/dev/null
ok "Sysctl parameters hardened"

info "Blacklisting dangerous kernel modules..."
cat > /etc/modprobe.d/ccdc-blacklist.conf << 'MODEOF'
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
install cramfs /bin/true
install freevxfs /bin/true
install hfs /bin/true
install hfsplus /bin/true
install udf /bin/true
MODEOF

for mod in dccp sctp rds tipc cramfs freevxfs hfs hfsplus udf; do
    rmmod "$mod" 2>/dev/null
done
ok "Dangerous kernel modules blacklisted"

info "Setting nproc limits (fork bomb defense)..."
cat >> /etc/security/limits.conf << 'LIMEOF'
# CCDC fork bomb defense
* soft nproc 1024
* hard nproc 2048
root soft nproc unlimited
root hard nproc unlimited
LIMEOF
ok "nproc limits set"

#=============================================================================
phase "6 - File Permission Hardening"
#=============================================================================

info "Securing critical files..."
chmod 644 /etc/passwd; chown root:root /etc/passwd
chmod 600 /etc/shadow 2>/dev/null; chown root:root /etc/shadow 2>/dev/null
chmod 644 /etc/group; chown root:root /etc/group
[ -f /etc/gshadow ] && chmod 600 /etc/gshadow && chown root:root /etc/gshadow
chmod 600 /etc/ssh/*_key 2>/dev/null
chmod 644 /etc/ssh/*.pub 2>/dev/null
chmod 440 /etc/sudoers 2>/dev/null
chmod 440 /etc/sudoers.d/* 2>/dev/null
ok "Critical file permissions set"

info "Securing cron directories..."
chmod 600 /etc/crontab 2>/dev/null
for d in /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.monthly /etc/cron.weekly; do
    [ -d "$d" ] && chmod 700 "$d"
done
ok "Cron directories secured"

info "Restricting cron and at access..."
echo "root" > /etc/cron.allow 2>/dev/null
chmod 600 /etc/cron.allow 2>/dev/null
rm -f /etc/cron.deny 2>/dev/null
echo "root" > /etc/at.allow 2>/dev/null
chmod 600 /etc/at.allow 2>/dev/null
rm -f /etc/at.deny 2>/dev/null
ok "Cron/at restricted to root"

info "Securing GRUB config..."
[ -f /boot/grub/grub.cfg ] && chmod 600 /boot/grub/grub.cfg
[ -f /boot/grub2/grub.cfg ] && chmod 600 /boot/grub2/grub.cfg

info "Securing home directories..."
for home in /home/*; do
    if [ -d "$home" ]; then
        user=$(basename "$home")
        chmod 700 "$home"
        [ -d "$home/.ssh" ] && chmod 700 "$home/.ssh" && chmod 600 "$home/.ssh"/* 2>/dev/null
        for dotfile in .bash_history .mysql_history .psql_history .viminfo; do
            [ -f "$home/$dotfile" ] && chmod 600 "$home/$dotfile"
        done
    fi
done
chmod 700 /root
[ -d /root/.ssh ] && chmod 700 /root/.ssh && chmod 600 /root/.ssh/* 2>/dev/null
ok "Home directories secured"

info "Removing world-writable from files..."
find / -xdev -type f -perm -0002 ! -path "/proc/*" ! -path "/sys/*" ! -path "/dev/*" 2>/dev/null | \
    head -200 | while read -r f; do
    chmod o-w "$f" 2>/dev/null
done

info "Adding sticky bit to world-writable directories..."
find / -xdev -type d \( -perm -0002 -a ! -perm -1000 \) ! -path "/proc/*" ! -path "/sys/*" ! -path "/dev/*" 2>/dev/null | \
    head -200 | while read -r d; do
    chmod +t "$d" 2>/dev/null
done
ok "World-writable files fixed"

#=============================================================================
phase "7 - Disable Dangerous Services"
#=============================================================================

DANGEROUS_SERVICES=(
    telnet telnetd xinetd inetd
    rsh rlogin rexec rsh-server
    tftp tftpd atftpd
    nfs nfs-server nfs-kernel-server rpcbind
    avahi-daemon cups cups-browsed
    bluetooth bluez
    snmpd
)

for svc in "${DANGEROUS_SERVICES[@]}"; do
    case "$INIT_SYSTEM" in
        systemd)
            if systemctl is-active "$svc" &>/dev/null || systemctl is-enabled "$svc" &>/dev/null; then
                svc_stop "$svc"
                info "Disabled: $svc"
            fi
            ;;
        *)
            if service "$svc" status &>/dev/null 2>&1; then
                svc_stop "$svc"
                info "Disabled: $svc"
            fi
            ;;
    esac
done
ok "Dangerous services disabled"

info "Checking for suspicious systemd units..."
if [ "$INIT_SYSTEM" = "systemd" ]; then
    for f in /etc/systemd/system/*.service; do
        [ -f "$f" ] || continue
        if grep -qE 'ExecStart=.*(nc |ncat |netcat |/tmp/|/dev/shm/|curl.*\||wget.*\|)' "$f" 2>/dev/null; then
            warn "Suspicious ExecStart in: $f"
        fi
    done
fi

#=============================================================================
phase "8 - Remove Unnecessary SUID"
#=============================================================================

REMOVE_SUID=("/usr/bin/wall" "/usr/bin/write" "/usr/bin/chage" "/usr/bin/expiry")
for binary in "${REMOVE_SUID[@]}"; do
    if [ -f "$binary" ]; then
        if [ -u "$binary" ] || [ -g "$binary" ]; then
            chmod u-s,g-s "$binary"
            info "Removed SUID/SGID from: $binary"
        fi
    fi
done
ok "Unnecessary SUID bits removed"

#=============================================================================
phase "9 - Clone Toolkit Repository"
#=============================================================================

if [ -d /opt/ccdc26 ]; then
    info "Toolkit already present at /opt/ccdc26"
else
    info "Cloning CCDC26 toolkit..."
    git clone https://github.com/byui-soc/ccdc26.git /opt/ccdc26 2>/dev/null || true
fi
ok "Toolkit clone step complete"

#=============================================================================
# SUMMARY
#=============================================================================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
phase "Hardening Complete"
ok "Finished in ${DURATION}s"
echo ""
echo "NEXT STEPS:"
echo "  1. Test SSH in a NEW terminal before closing this session"
echo "  2. Run 02-firewall.sh to set up firewall rules"
echo "  3. Run 03-services.sh to harden application services"
echo "  4. Run hunt-persistence.sh to find attacker persistence"
echo ""
