#!/bin/bash
# CCDC26 Monarch - Wazuh Agent Installer
# Installs the Wazuh HIDS agent and registers with a Wazuh manager.
# Provides file integrity monitoring, rootkit detection, and log analysis.
# Alerts forward through the manager to Splunk for centralized visibility.
# SELF-CONTAINED -- no external dependencies.
# Usage: setup-wazuh.sh [MANAGER_IP]   (or reads WAZUH_MANAGER from env)

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

#=============================================================================
# CONFIGURATION
#=============================================================================
MANAGER_IP="${1:-${WAZUH_MANAGER:-}}"
AGENT_NAME="$(hostname)"
AGENT_GROUP="linux-agents"
WAZUH_VERSION="4.7.5-1"
WAZUH_REPO="4.x"

if [ -z "$MANAGER_IP" ]; then
    error "Wazuh manager IP not set."
    error "Usage: setup-wazuh.sh <MANAGER_IP>"
    error "Or export WAZUH_MANAGER in config.env"
    exit 1
fi

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

START_TIME=$(date +%s)
echo ""
echo -e "${BOLD}${GREEN}CCDC26 Monarch - Wazuh HIDS Agent Setup${NC}"
echo -e "${BOLD}Host: $(hostname) | $(date) | $DISTRO_FAMILY / $PKG_MGR${NC}"
echo -e "${BOLD}Manager: $MANAGER_IP | Version: $WAZUH_VERSION${NC}"
echo ""

#=============================================================================
phase "1 - Stop Background Package Managers"
#=============================================================================

systemctl stop unattended-upgrades 2>/dev/null || true
systemctl disable unattended-upgrades 2>/dev/null || true
killall unattended-upgrades 2>/dev/null || true
rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock 2>/dev/null || true
dpkg --configure -a 2>/dev/null || true
sleep 1
ok "Background package managers cleared"

#=============================================================================
phase "2 - Check Existing Installation"
#=============================================================================

if systemctl is-active --quiet wazuh-agent 2>/dev/null; then
    EXISTING_MGR=$(grep -oP '<address>\K[^<]+' /var/ossec/etc/ossec.conf 2>/dev/null || echo "unknown")
    if [ "$EXISTING_MGR" = "$MANAGER_IP" ]; then
        ok "Wazuh agent already installed and pointing to $MANAGER_IP"
        info "Restarting agent to apply any config changes..."
        systemctl restart wazuh-agent
        ok "Agent restarted. Done."
        exit 0
    else
        warn "Agent installed but pointing to $EXISTING_MGR (want $MANAGER_IP)"
        info "Reconfiguring..."
    fi
fi

#=============================================================================
phase "3 - Open Firewall for Download"
#=============================================================================

FW_OPENED=false
if command -v iptables &>/dev/null; then
    info "Opening outbound 80/443 for package download..."
    iptables -I OUTPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null
    iptables -I OUTPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null
    FW_OPENED=true
fi

fw_close() {
    if [ "$FW_OPENED" = true ] && command -v iptables &>/dev/null; then
        info "Closing temporary outbound rules..."
        iptables -D OUTPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null
        iptables -D OUTPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null
    fi
}
trap fw_close EXIT

#=============================================================================
phase "4 - Add Wazuh Repository"
#=============================================================================

case "$PKG_MGR" in
    apt)
        info "Adding Wazuh APT repository..."
        apt-get install -y -qq curl gnupg2 apt-transport-https &>/dev/null
        curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --dearmor -o /usr/share/keyrings/wazuh.gpg 2>/dev/null
        echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/${WAZUH_REPO}/apt/ stable main" \
            > /etc/apt/sources.list.d/wazuh.list
        apt-get update -qq 2>/dev/null
        ok "APT repository added"
        ;;
    dnf|yum)
        info "Adding Wazuh YUM/DNF repository..."
        rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH 2>/dev/null
        cat > /etc/yum.repos.d/wazuh.repo << 'REPO'
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
REPO
        ok "YUM/DNF repository added"
        ;;
    *)
        error "Unsupported package manager: $PKG_MGR"
        exit 1
        ;;
esac

#=============================================================================
phase "5 - Install Wazuh Agent v$WAZUH_VERSION"
#=============================================================================

case "$PKG_MGR" in
    apt)
        WAZUH_MANAGER="$MANAGER_IP" \
        WAZUH_AGENT_NAME="$AGENT_NAME" \
        WAZUH_AGENT_GROUP="$AGENT_GROUP" \
        apt-get install -y wazuh-agent=${WAZUH_VERSION} 2>&1 | tail -5
        ;;
    dnf|yum)
        WAZUH_MANAGER="$MANAGER_IP" \
        WAZUH_AGENT_NAME="$AGENT_NAME" \
        WAZUH_AGENT_GROUP="$AGENT_GROUP" \
        $PKG_MGR install -y wazuh-agent-${WAZUH_VERSION} 2>&1 | tail -5
        ;;
esac

if [ ! -d /var/ossec ]; then
    error "Wazuh agent installation failed -- /var/ossec not found"
    exit 1
fi
ok "Wazuh agent v$WAZUH_VERSION installed"

#=============================================================================
phase "6 - Configure Agent"
#=============================================================================

cat > /var/ossec/etc/ossec.conf << EOF
<ossec_config>

  <client>
    <server>
      <address>${MANAGER_IP}</address>
      <port>1514</port>
      <protocol>tcp</protocol>
    </server>
    <enrollment>
      <enabled>yes</enabled>
    </enrollment>
  </client>

  <client_buffer>
    <disabled>no</disabled>
    <queue_size>5000</queue_size>
    <events_per_second>500</events_per_second>
  </client_buffer>

  <!-- Log sources -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/auth.log</location>
  </localfile>

  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/syslog</location>
  </localfile>

  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/kern.log</location>
  </localfile>

  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/dpkg.log</location>
  </localfile>

  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/secure</location>
  </localfile>

  <localfile>
    <log_format>apache</log_format>
    <location>/var/log/apache2/access.log</location>
  </localfile>

  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/nginx/access.log</location>
  </localfile>

  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/cron</location>
  </localfile>

</ossec_config>
EOF

ok "ossec.conf written (manager: $MANAGER_IP)"

#=============================================================================
phase "7 - Register and Start Agent"
#=============================================================================

/var/ossec/bin/agent-auth -m "$MANAGER_IP" 2>&1 && ok "Agent registered with manager" || warn "Registration failed -- check manager connectivity on port 1515"

systemctl daemon-reload
systemctl enable wazuh-agent 2>/dev/null
systemctl start wazuh-agent

sleep 3
if systemctl is-active --quiet wazuh-agent; then
    ok "Wazuh agent is RUNNING"
else
    warn "Agent not running -- attempting manual start..."
    /var/ossec/bin/wazuh-control start 2>/dev/null || true
    sleep 2
    if systemctl is-active --quiet wazuh-agent 2>/dev/null; then
        ok "Agent started on second attempt"
    else
        error "Agent failed to start -- check: journalctl -u wazuh-agent"
    fi
fi

# Pin version to prevent auto-upgrades
if command -v apt-mark &>/dev/null; then
    apt-mark hold wazuh-agent &>/dev/null
fi

#=============================================================================
phase "8 - Open Firewall for Manager Communication"
#=============================================================================

if command -v iptables &>/dev/null; then
    iptables -I OUTPUT -p tcp -d "$MANAGER_IP" --dport 1514 -j ACCEPT 2>/dev/null
    iptables -I OUTPUT -p tcp -d "$MANAGER_IP" --dport 1515 -j ACCEPT 2>/dev/null
    ok "Firewall rules added for manager $MANAGER_IP (1514/1515)"
fi

#=============================================================================
phase "9 - Verify Connectivity"
#=============================================================================

for port in 1514 1515; do
    if command -v nc &>/dev/null; then
        if nc -zw3 "$MANAGER_IP" $port 2>/dev/null; then
            ok "Port $port reachable on $MANAGER_IP"
        else
            warn "Port $port NOT reachable on $MANAGER_IP -- check network/firewall"
        fi
    else
        info "nc not available -- skipping port check for $port"
    fi
done

#=============================================================================
# SUMMARY
#=============================================================================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
phase "Wazuh Agent Setup Complete"
ok "Finished in ${DURATION}s"
echo ""
echo "CONFIGURATION:"
echo "  Agent name:   $AGENT_NAME"
echo "  Manager IP:   $MANAGER_IP"
echo "  Version:      $WAZUH_VERSION (pinned)"
echo "  Config:       /var/ossec/etc/ossec.conf"
echo "  Agent log:    /var/ossec/logs/ossec.log"
echo "  Status:       systemctl status wazuh-agent"
echo ""
echo "WHAT THIS GIVES YOU:"
echo "  - File integrity monitoring (FIM)"
echo "  - Rootkit detection"
echo "  - Log analysis with 3000+ built-in detection rules"
echo "  - Alerts forwarded to manager -> Splunk"
echo ""
echo "SPLUNK INTEGRATION:"
echo "  Run dark3v3's wazuh-to-splunk.sh on the Wazuh manager to forward"
echo "  alerts to Splunk. Search with: index=wazuh-alerts"
echo ""
