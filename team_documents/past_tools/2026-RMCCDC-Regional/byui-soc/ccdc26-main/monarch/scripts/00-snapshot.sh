#!/bin/bash
# CCDC26 Monarch - Pre-Hardening Forensic Snapshot
# Takes a complete system baseline before any changes are made
# SELF-CONTAINED -- no external dependencies

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
phase() { echo -e "\n${BOLD}${PURPLE}[PHASE] $1${NC}\n"; }

if [ "$EUID" -ne 0 ]; then
    error "Must be run as root"
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SNAP_DIR="/root/ccdc-snapshot-${TIMESTAMP}"
mkdir -p "$SNAP_DIR"

phase "System Identity"
{
    echo "=== SNAPSHOT TIMESTAMP ==="
    date -u
    echo ""
    echo "=== HOSTNAME ==="
    hostname
    echo ""
    echo "=== IP ADDRESSES ==="
    ip -4 addr show 2>/dev/null || ifconfig 2>/dev/null
    echo ""
    echo "=== UPTIME ==="
    uptime
    echo ""
    echo "=== KERNEL ==="
    uname -a
    echo ""
    echo "=== OS RELEASE ==="
    cat /etc/os-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null || echo "unknown"
} > "$SNAP_DIR/system-identity.txt"
ok "System identity recorded"

phase "User & Auth Data"
cp /etc/passwd "$SNAP_DIR/passwd" 2>/dev/null
awk -F: '{print $1":"$2}' /etc/shadow > "$SNAP_DIR/shadow-hashes" 2>/dev/null
cp /etc/group "$SNAP_DIR/group" 2>/dev/null
cp /etc/sudoers "$SNAP_DIR/sudoers" 2>/dev/null
cp -r /etc/sudoers.d "$SNAP_DIR/sudoers.d" 2>/dev/null
ok "User and auth data saved"

phase "Running Processes"
ps auxf > "$SNAP_DIR/ps-auxf.txt" 2>/dev/null
ps -eo pid,ppid,user,uid,args --sort=-pcpu > "$SNAP_DIR/ps-sorted.txt" 2>/dev/null
ok "Process list saved"

phase "Network State"
{
    echo "=== LISTENING PORTS ==="
    ss -tulpn 2>/dev/null || netstat -tulpn 2>/dev/null
    echo ""
    echo "=== ALL CONNECTIONS ==="
    ss -tunapl 2>/dev/null || netstat -an 2>/dev/null
    echo ""
    echo "=== ROUTING TABLE ==="
    ip route 2>/dev/null || route -n 2>/dev/null
    echo ""
    echo "=== ARP TABLE ==="
    ip neigh 2>/dev/null || arp -an 2>/dev/null
} > "$SNAP_DIR/network-state.txt"
ok "Network state saved"

phase "Crontabs (All Users)"
{
    echo "=== /etc/crontab ==="
    cat /etc/crontab 2>/dev/null
    echo ""
    echo "=== /etc/cron.d/ ==="
    for f in /etc/cron.d/*; do
        [ -f "$f" ] && echo "--- $f ---" && cat "$f"
    done
    echo ""
    echo "=== User Crontabs ==="
    for user in $(cut -d: -f1 /etc/passwd); do
        ct=$(crontab -l -u "$user" 2>/dev/null)
        if [ -n "$ct" ]; then
            echo "--- $user ---"
            echo "$ct"
        fi
    done
    echo ""
    echo "=== Anacron ==="
    cat /etc/anacrontab 2>/dev/null || echo "no anacrontab"
} > "$SNAP_DIR/crontabs.txt"
ok "Crontabs saved"

phase "Firewall Rules"
{
    echo "=== iptables ==="
    iptables -L -n -v 2>/dev/null || echo "iptables not available"
    echo ""
    iptables-save 2>/dev/null || true
    echo ""
    echo "=== nftables ==="
    nft list ruleset 2>/dev/null || echo "nftables not available"
    echo ""
    echo "=== ufw ==="
    ufw status verbose 2>/dev/null || echo "ufw not available"
    echo ""
    echo "=== firewalld ==="
    firewall-cmd --list-all 2>/dev/null || echo "firewalld not available"
} > "$SNAP_DIR/firewall-rules.txt"
ok "Firewall rules saved"

phase "Systemd Services"
{
    echo "=== Running Services ==="
    systemctl list-units --type=service --state=running --no-pager 2>/dev/null || service --status-all 2>/dev/null
    echo ""
    echo "=== Enabled Services ==="
    systemctl list-unit-files --type=service --state=enabled --no-pager 2>/dev/null
    echo ""
    echo "=== Timers ==="
    systemctl list-timers --all --no-pager 2>/dev/null
} > "$SNAP_DIR/services.txt"
ok "Service list saved"

phase "SSH Configuration"
cp /etc/ssh/sshd_config "$SNAP_DIR/sshd_config" 2>/dev/null
{
    echo "=== Authorized Keys ==="
    for home in /home/* /root; do
        [ -f "$home/.ssh/authorized_keys" ] && echo "--- $home ---" && cat "$home/.ssh/authorized_keys"
    done
} > "$SNAP_DIR/ssh-authorized-keys.txt"
ok "SSH config saved"

phase "Installed Packages"
{
    if command -v dpkg &>/dev/null; then
        dpkg -l
    elif command -v rpm &>/dev/null; then
        rpm -qa | sort
    elif command -v apk &>/dev/null; then
        apk list --installed
    elif command -v pacman &>/dev/null; then
        pacman -Q
    fi
} > "$SNAP_DIR/packages.txt" 2>/dev/null
ok "Package list saved"

phase "SUID/SGID & Capabilities"
{
    echo "=== SUID Binaries ==="
    find / -xdev -type f -perm -4000 2>/dev/null | sort
    echo ""
    echo "=== SGID Binaries ==="
    find / -xdev -type f -perm -2000 2>/dev/null | sort
    echo ""
    echo "=== File Capabilities ==="
    getcap -r / 2>/dev/null || echo "getcap not available"
} > "$SNAP_DIR/suid-sgid-caps.txt"
ok "SUID/SGID/capabilities saved"

phase "Critical File Hashes"
{
    for f in /etc/passwd /etc/shadow /etc/group /etc/sudoers \
             /etc/ssh/sshd_config /etc/pam.d/sshd /etc/pam.d/common-auth \
             /usr/bin/sudo /usr/bin/su /usr/sbin/sshd /bin/bash /bin/sh \
             /etc/ld.so.preload /etc/crontab; do
        [ -f "$f" ] && sha256sum "$f"
    done
} > "$SNAP_DIR/critical-hashes.txt" 2>/dev/null
ok "Critical file hashes saved"

phase "PAM Configuration"
cp -r /etc/pam.d "$SNAP_DIR/pam.d" 2>/dev/null
ok "PAM config saved"

phase "LD_PRELOAD Check"
{
    echo "=== LD_PRELOAD env ==="
    env | grep -i preload || echo "(not set)"
    echo ""
    echo "=== /etc/ld.so.preload ==="
    cat /etc/ld.so.preload 2>/dev/null || echo "(does not exist)"
    echo ""
    echo "=== /etc/ld.so.conf.d/ ==="
    for f in /etc/ld.so.conf.d/*; do
        [ -f "$f" ] && echo "--- $f ---" && cat "$f"
    done
} > "$SNAP_DIR/ld-preload.txt"
ok "LD_PRELOAD check saved"

phase "Creating Snapshot Archive"
TARBALL="/root/ccdc-snapshot-${TIMESTAMP}.tar.gz"
tar -czf "$TARBALL" -C /root "ccdc-snapshot-${TIMESTAMP}"
rm -rf "$SNAP_DIR"
ok "Snapshot archived: $TARBALL"
info "Size: $(du -h "$TARBALL" | awk '{print $1}')"

echo ""
echo -e "${GREEN}${BOLD}Forensic snapshot complete.${NC}"
echo "Archive: $TARBALL"
