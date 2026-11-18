#!/bin/bash
# CCDC26 Monarch - Suricata IDS Setup
# Installs Suricata in IDS (passive) mode with ET Open community rules.
# Monitors network traffic for known attack signatures without dropping packets.
# SELF-CONTAINED -- no external dependencies.

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

if [ "$EUID" -ne 0 ]; then error "Must be run as root"; exit 1; fi

# Distro detection
DISTRO_FAMILY="unknown"; PKG_MGR="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        ubuntu|debian|kali|mint|pop) DISTRO_FAMILY="debian"; PKG_MGR="apt" ;;
        rhel|centos|fedora|rocky|alma|oracle)
            DISTRO_FAMILY="rhel"
            command -v dnf &>/dev/null && PKG_MGR="dnf" || PKG_MGR="yum"
            ;;
    esac
fi

SURICATA_CONF="/etc/suricata/suricata.yaml"
LOG_DIR="/var/log/suricata"

START_TIME=$(date +%s)
echo ""
echo -e "${BOLD}${GREEN}CCDC26 Monarch - Suricata IDS Setup${NC}"
echo -e "${BOLD}Host: $(hostname) | $(date) | $DISTRO_FAMILY / $PKG_MGR${NC}"
echo ""

#=============================================================================
phase "1 - Install Suricata"
#=============================================================================

case "$PKG_MGR" in
    apt)
        info "Installing Suricata via apt..."
        apt-get update -qq
        apt-get install -y -qq suricata suricata-update &>/dev/null
        ;;
    dnf|yum)
        info "Installing Suricata via $PKG_MGR..."
        $PKG_MGR install -y -q epel-release &>/dev/null 2>&1 || true
        $PKG_MGR install -y -q suricata &>/dev/null
        ;;
    *)
        error "Unsupported package manager: $PKG_MGR"
        exit 1
        ;;
esac

if ! command -v suricata &>/dev/null; then
    error "Suricata installation failed"
    exit 1
fi
ok "Suricata $(suricata --build-info 2>/dev/null | head -1 | grep -oP 'Suricata \K[0-9.]+' || suricata -V 2>&1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' || echo '(version unknown)') installed"

#=============================================================================
phase "2 - Detect Network Interface"
#=============================================================================

IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
if [ -z "$IFACE" ]; then
    IFACE=$(ip -o link show up 2>/dev/null | awk -F': ' '!/lo/{print $2; exit}')
fi
if [ -z "$IFACE" ]; then
    error "Could not detect network interface. Set IFACE manually and re-run."
    exit 1
fi
ok "Primary interface: $IFACE"

# Auto-detect HOME_NET from interface IP/subnet
IFACE_CIDR=$(ip -o -4 addr show "$IFACE" 2>/dev/null | awk '{print $4}')
if [ -n "$IFACE_CIDR" ]; then
    HOME_NET="[${IFACE_CIDR}]"
    ok "HOME_NET: $HOME_NET"
else
    HOME_NET="[192.168.0.0/16,10.0.0.0/8,172.16.0.0/12]"
    warn "Could not detect subnet, using RFC1918 ranges: $HOME_NET"
fi

#=============================================================================
phase "3 - Download Rules"
#=============================================================================

mkdir -p "$LOG_DIR"

info "Running suricata-update to fetch ET Open community rules..."
suricata-update 2>&1 | tail -5
ok "Rules downloaded"

#=============================================================================
phase "4 - Configure Suricata"
#=============================================================================

if [ ! -f "$SURICATA_CONF" ]; then
    error "Suricata config not found at $SURICATA_CONF"
    exit 1
fi
backup_file() {
    local f="$1"
    [ -f "$f" ] && cp "$f" "${f}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null
}
backup_file "$SURICATA_CONF"

# Set HOME_NET
sed -i "s|HOME_NET:.*|HOME_NET: \"$HOME_NET\"|" "$SURICATA_CONF"
ok "HOME_NET set to $HOME_NET"

# Set monitored interface (af-packet section)
if grep -q 'af-packet:' "$SURICATA_CONF"; then
    sed -i "/af-packet:/,/- interface:/{s/- interface: .*/- interface: $IFACE/}" "$SURICATA_CONF"
    ok "af-packet interface set to $IFACE"
fi

# Enable community-id for Splunk correlation
if grep -q 'community-id:' "$SURICATA_CONF"; then
    sed -i 's/community-id: .*/community-id: true/' "$SURICATA_CONF"
else
    sed -i '/^outputs:/a\  - community-id: true' "$SURICATA_CONF"
fi
ok "Community ID enabled (Splunk correlation)"

# Ensure EVE JSON logging is on (primary log format for Splunk)
if grep -q 'eve-log:' "$SURICATA_CONF"; then
    ok "EVE JSON log already configured"
else
    warn "EVE log section not found -- Suricata should produce eve.json by default"
fi

# Ensure log directory
sed -i "s|default-log-dir: .*|default-log-dir: $LOG_DIR|" "$SURICATA_CONF"
ok "Log directory set to $LOG_DIR"

#=============================================================================
phase "5 - Start Suricata (IDS Mode)"
#=============================================================================

warn "Suricata runs in IDS mode (passive). It will NOT drop traffic."

if [ -d /run/systemd/system ]; then
    # Set the interface in the systemd override
    mkdir -p /etc/systemd/system/suricata.service.d
    cat > /etc/systemd/system/suricata.service.d/interface.conf << EOF
[Service]
ExecStart=
ExecStart=/usr/bin/suricata -c $SURICATA_CONF --af-packet=$IFACE --pidfile /run/suricata.pid
EOF
    systemctl daemon-reload
    systemctl enable suricata 2>/dev/null
    systemctl restart suricata
    sleep 2
    if systemctl is-active suricata &>/dev/null; then
        ok "Suricata running and enabled"
    else
        error "Suricata failed to start -- check: journalctl -u suricata"
    fi
else
    suricata -c "$SURICATA_CONF" --af-packet="$IFACE" -D --pidfile /run/suricata.pid
    ok "Suricata started in background (PID: $(cat /run/suricata.pid 2>/dev/null || echo 'unknown'))"
fi

#=============================================================================
# SUMMARY
#=============================================================================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
phase "IDS Setup Complete"
ok "Finished in ${DURATION}s"
echo ""
echo "CONFIGURATION:"
echo "  Interface:    $IFACE"
echo "  HOME_NET:     $HOME_NET"
echo "  Config:       $SURICATA_CONF"
echo "  Log dir:      $LOG_DIR"
echo "  Mode:         IDS (passive monitoring, no packet drops)"
echo "  Key logs:     $LOG_DIR/eve.json  (alerts + flow + dns + http)"
echo "                $LOG_DIR/fast.log  (one-line alert summary)"
echo ""
echo "SPLUNK INTEGRATION (add to inputs.conf):"
echo "  [monitor://$LOG_DIR/eve.json]"
echo "  sourcetype = suricata"
echo "  index = security"
echo ""
echo "RULE UPDATES:"
echo "  Run 'suricata-update' periodically, then 'suricatasc -c reload-rules'"
echo ""
