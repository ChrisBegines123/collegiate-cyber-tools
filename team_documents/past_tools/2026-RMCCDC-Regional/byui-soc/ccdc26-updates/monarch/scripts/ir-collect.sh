#!/bin/bash
# CCDC26 Monarch - Evidence Collection
# Tar up logs, process list, network state, memory info
# SELF-CONTAINED -- no external dependencies

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then error "Must be run as root"; exit 1; fi

TS=$(date +%Y%m%d_%H%M%S)
EDIR="/tmp/evidence-$(hostname)-${TS}"
mkdir -p "$EDIR"/{system,users,processes,network,logs,persistence}

echo -e "\n${BOLD}CCDC26 Evidence Collection${NC}\n"
info "Collecting to $EDIR"

# System
info "System info..."
hostname > "$EDIR/system/hostname.txt"
date > "$EDIR/system/date.txt"
uname -a > "$EDIR/system/uname.txt"
uptime > "$EDIR/system/uptime.txt"
cat /etc/os-release > "$EDIR/system/os-release.txt" 2>/dev/null

# Users
info "User data..."
cp /etc/passwd /etc/group "$EDIR/users/" 2>/dev/null
cp /etc/shadow "$EDIR/users/" 2>/dev/null
who -a > "$EDIR/users/who.txt" 2>/dev/null
last > "$EDIR/users/last.txt" 2>/dev/null
for home in /home/* /root; do
    user=$(basename "$home"); [ "$home" = "/root" ] && user="root"
    [ -f "$home/.bash_history" ] && cp "$home/.bash_history" "$EDIR/users/${user}_bash_history" 2>/dev/null
    [ -d "$home/.ssh" ] && cp -r "$home/.ssh" "$EDIR/users/${user}_ssh" 2>/dev/null
done

# Processes
info "Processes..."
ps auxf > "$EDIR/processes/ps-auxf.txt" 2>/dev/null
ps -eo pid,ppid,user,uid,args > "$EDIR/processes/ps-full.txt" 2>/dev/null
cat /proc/meminfo > "$EDIR/processes/meminfo.txt" 2>/dev/null
lsmod > "$EDIR/processes/modules.txt" 2>/dev/null

# Network
info "Network state..."
ss -tunapl > "$EDIR/network/ss.txt" 2>/dev/null
ip addr > "$EDIR/network/ip-addr.txt" 2>/dev/null
ip route > "$EDIR/network/ip-route.txt" 2>/dev/null
ip neigh > "$EDIR/network/arp.txt" 2>/dev/null
iptables -L -n -v > "$EDIR/network/iptables.txt" 2>/dev/null
iptables-save > "$EDIR/network/iptables-save.txt" 2>/dev/null
cat /etc/hosts > "$EDIR/network/hosts.txt" 2>/dev/null
cat /etc/resolv.conf > "$EDIR/network/resolv.txt" 2>/dev/null

# Logs
info "Logs..."
for log in /var/log/auth.log /var/log/secure /var/log/syslog /var/log/messages \
           /var/log/kern.log /var/log/cron /var/log/audit/audit.log; do
    [ -f "$log" ] && cp "$log" "$EDIR/logs/" 2>/dev/null
done
journalctl --since "24 hours ago" > "$EDIR/logs/journald-24h.log" 2>/dev/null

# Persistence
info "Persistence artifacts..."
cp /etc/crontab "$EDIR/persistence/" 2>/dev/null
cp -r /etc/cron.d "$EDIR/persistence/" 2>/dev/null
for user in $(cut -d: -f1 /etc/passwd); do
    crontab -l -u "$user" > "$EDIR/persistence/crontab-$user" 2>/dev/null
done
systemctl list-units --type=service > "$EDIR/persistence/services.txt" 2>/dev/null

# Critical hashes
info "Hashing critical files..."
{
    for f in /etc/passwd /etc/shadow /etc/group /etc/sudoers /etc/ssh/sshd_config \
             /usr/bin/sudo /usr/bin/su /usr/sbin/sshd /bin/bash /bin/sh; do
        [ -f "$f" ] && sha256sum "$f"
    done
} > "$EDIR/critical-hashes.txt" 2>/dev/null

# Package
info "Creating archive..."
TARBALL="/tmp/evidence-$(hostname)-${TS}.tar.gz"
tar -czf "$TARBALL" -C /tmp "$(basename "$EDIR")" 2>/dev/null
sha256sum "$TARBALL" > "${TARBALL}.sha256"
rm -rf "$EDIR"

echo ""
ok "Evidence collected"
info "Archive: $TARBALL"
info "SHA256: $(cat "${TARBALL}.sha256")"
info "Size: $(du -h "$TARBALL" | awk '{print $1}')"
