#!/bin/bash
# CCDC26 Monarch - Monitoring Deployment
# Install auditd, set up file integrity baseline, deploy process monitor
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

# Distro/package manager detection
PKG_MGR="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        ubuntu|debian|kali|mint|pop) PKG_MGR="apt" ;;
        rhel|centos|fedora|rocky|alma|oracle)
            command -v dnf &>/dev/null && PKG_MGR="dnf" || PKG_MGR="yum"
            ;;
        alpine) PKG_MGR="apk" ;;
        arch|manjaro) PKG_MGR="pacman" ;;
    esac
fi

pkg_install() {
    local pkg="$1"
    case "$PKG_MGR" in
        apt)     apt-get install -y -qq "$pkg" 2>/dev/null ;;
        dnf|yum) $PKG_MGR install -y -q "$pkg" 2>/dev/null ;;
        apk)     apk add -q "$pkg" 2>/dev/null ;;
        pacman)  pacman -S --noconfirm --quiet "$pkg" 2>/dev/null ;;
    esac
}

INIT_SYSTEM="unknown"
[ -d /run/systemd/system ] && INIT_SYSTEM="systemd"

#=============================================================================
phase "1 - Auditd Installation & Configuration"
#=============================================================================

if ! command -v auditctl &>/dev/null; then
    info "Installing auditd..."
    pkg_install auditd 2>/dev/null || pkg_install audit 2>/dev/null
fi

if command -v auditctl &>/dev/null; then
    info "Configuring audit rules..."

    AUDIT_RULES="/etc/audit/rules.d/ccdc.rules"
    mkdir -p /etc/audit/rules.d

    cat > "$AUDIT_RULES" << 'EOF'
# CCDC26 Audit Rules

# Delete all existing rules
-D

# Buffer size
-b 8192

# Failure mode (1=printk, 2=panic)
-f 1

# Process execution
-a always,exit -F arch=b64 -S execve -k exec
-a always,exit -F arch=b32 -S execve -k exec

# File changes - critical files
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# SSH keys
-w /root/.ssh/ -p wa -k ssh_keys
-w /home/ -p wa -k home_changes

# Cron
-w /etc/crontab -p wa -k cron
-w /etc/cron.d/ -p wa -k cron
-w /etc/cron.daily/ -p wa -k cron
-w /etc/cron.hourly/ -p wa -k cron
-w /var/spool/cron/ -p wa -k cron

# PAM
-w /etc/pam.d/ -p wa -k pam
-w /etc/security/ -p wa -k pam

# LD_PRELOAD
-w /etc/ld.so.preload -p wa -k preload
-w /etc/ld.so.conf -p wa -k preload
-w /etc/ld.so.conf.d/ -p wa -k preload

# SSH config
-w /etc/ssh/sshd_config -p wa -k sshd_config

# Systemd services
-w /etc/systemd/system/ -p wa -k systemd
-w /lib/systemd/system/ -p wa -k systemd
-w /usr/lib/systemd/system/ -p wa -k systemd

# Network config
-w /etc/hosts -p wa -k network
-w /etc/resolv.conf -p wa -k network
-w /etc/network/ -p wa -k network

# Kernel modules
-a always,exit -F arch=b64 -S init_module -S finit_module -k modules
-a always,exit -F arch=b64 -S delete_module -k modules

# Time changes
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time
-w /etc/localtime -p wa -k time

# Immutable mode (must be last)
-e 2
EOF

    # Load rules
    if command -v augenrules &>/dev/null; then
        augenrules --load 2>/dev/null
    else
        auditctl -R "$AUDIT_RULES" 2>/dev/null
    fi

    # Enable and start auditd
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl enable auditd 2>/dev/null
        systemctl restart auditd 2>/dev/null
    else
        service auditd restart 2>/dev/null
    fi

    ok "Auditd configured with comprehensive rules"
else
    warn "Could not install auditd"
fi

#=============================================================================
phase "2 - File Integrity Baseline"
#=============================================================================

BASELINE_DIR="/var/lib/ccdc-integrity"
mkdir -p "$BASELINE_DIR"
BASELINE="$BASELINE_DIR/baseline.sha256"

info "Creating file integrity baseline..."

CRITICAL_PATHS=(
    /etc/passwd /etc/shadow /etc/group /etc/gshadow
    /etc/sudoers /etc/ssh/sshd_config
    /etc/pam.d/sshd /etc/pam.d/common-auth /etc/pam.d/system-auth
    /etc/crontab /etc/ld.so.preload /etc/ld.so.conf
    /usr/bin/sudo /usr/bin/su /usr/bin/passwd
    /usr/sbin/sshd /bin/bash /bin/sh
    /usr/bin/ssh /usr/bin/crontab /usr/bin/login
)

> "$BASELINE"
for f in "${CRITICAL_PATHS[@]}"; do
    [ -f "$f" ] && sha256sum "$f" >> "$BASELINE"
done

# Also baseline all PAM modules
if [ -d /lib/x86_64-linux-gnu/security ]; then
    sha256sum /lib/x86_64-linux-gnu/security/pam_*.so >> "$BASELINE" 2>/dev/null
elif [ -d /lib64/security ]; then
    sha256sum /lib64/security/pam_*.so >> "$BASELINE" 2>/dev/null
fi

ok "Baseline saved to $BASELINE ($(wc -l < "$BASELINE") files)"

# Create verification script
cat > "$BASELINE_DIR/check-integrity.sh" << 'CHECKEOF'
#!/bin/bash
BASELINE="/var/lib/ccdc-integrity/baseline.sha256"
if [ ! -f "$BASELINE" ]; then
    echo "[ERROR] No baseline found"
    exit 1
fi
CHANGES=0
while IFS= read -r line; do
    expected_hash=$(echo "$line" | awk '{print $1}')
    filepath=$(echo "$line" | awk '{print $2}')
    [ -f "$filepath" ] || continue
    current_hash=$(sha256sum "$filepath" | awk '{print $1}')
    if [ "$expected_hash" != "$current_hash" ]; then
        echo "[ALERT] MODIFIED: $filepath"
        CHANGES=$((CHANGES + 1))
    fi
done < "$BASELINE"
if [ "$CHANGES" -eq 0 ]; then
    echo "[OK] All files match baseline"
else
    echo "[WARN] $CHANGES file(s) modified since baseline"
fi
CHECKEOF
chmod +x "$BASELINE_DIR/check-integrity.sh"
ok "Integrity check script: $BASELINE_DIR/check-integrity.sh"

#=============================================================================
phase "3 - Background Process Monitor"
#=============================================================================

MONITOR_SCRIPT="/usr/local/bin/ccdc-process-monitor.sh"

cat > "$MONITOR_SCRIPT" << 'MONEOF'
#!/bin/bash
# CCDC26 Process Monitor - logs new process creation to syslog
KNOWN_PIDS="/tmp/.ccdc-known-pids"
ps -eo pid --no-headers | tr -d ' ' | sort -n > "$KNOWN_PIDS"

while true; do
    sleep 10
    CURRENT="/tmp/.ccdc-current-pids"
    ps -eo pid,ppid,user,args --no-headers > "$CURRENT.full"
    awk '{print $1}' "$CURRENT.full" | sort -n > "$CURRENT"

    comm -13 "$KNOWN_PIDS" "$CURRENT" | while read -r pid; do
        info=$(grep "^ *$pid " "$CURRENT.full")
        if [ -n "$info" ]; then
            logger -t "CCDC-PROCMON" "NEW: $info"
        fi
    done

    mv "$CURRENT" "$KNOWN_PIDS"
    rm -f "$CURRENT.full"
done
MONEOF
chmod +x "$MONITOR_SCRIPT"

# Start in background
if [ -f /var/run/ccdc-procmon.pid ]; then
    kill "$(cat /var/run/ccdc-procmon.pid)" 2>/dev/null
fi
nohup "$MONITOR_SCRIPT" > /var/log/ccdc-procmon.log 2>&1 &
echo $! > /var/run/ccdc-procmon.pid
ok "Process monitor started (PID: $(cat /var/run/ccdc-procmon.pid))"
info "Logs: syslog (tag CCDC-PROCMON) and /var/log/ccdc-procmon.log"

echo ""
ok "Monitoring deployment complete"
echo ""
echo "Deployed:"
echo "  - Auditd with comprehensive rules"
echo "  - File integrity baseline ($BASELINE)"
echo "  - Background process monitor"
echo ""
echo "To check integrity: $BASELINE_DIR/check-integrity.sh"
echo "To stop process monitor: kill \$(cat /var/run/ccdc-procmon.pid)"
