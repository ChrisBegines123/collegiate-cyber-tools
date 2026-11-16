#!/bin/bash 
# ==============================================================================
# Script Name : splunkharden.sh
# Description : This is specifically to harden the Splunk server.
# Author      : Tyler Olson
# Organization: Missouri State University
# ==============================================================================
# Usage       : splunkharden.sh
# Notes       : 
#   - Designed to secure Splunk against red team attacks.
#   - Integrates Lynis for hardening validation and auditd for rename detection.
# ==============================================================================
# Changelog:
#   v0.9 - Initial draft (not complete).
#   v1.0 - Functional hardening with backups and SSH/firewall updates.
#   v1.1 - Added Lynis scoring, red team rename detection, and improved logging.
# ==============================================================================

# Defined variables:
defaultUsers=("root" "sysadmin")
sudo_password="changemenow"
new_password="password"
splunk_version="9.1.1"
backupip="172.20.20.20"
backup_account="root"
SPLUNK_HOME="/opt/splunk"
ALLOWED_IPS="172.20.20.0/24"  # Customize for your network
SSH_PORT=22
SPLUNK_WEB_PORT=8000
SPLUNK_MGMT_PORT=8089
LOG_FILE="/var/log/splunk_hardening.log"

# I love the colors
RED=$'\e[0;31m'; GREEN=$'\e[0;32m'; YELLOW=$'\e[0;33m'; BLUE=$'\e[0;34m'; NC=$'\e[0m'  # No Color - resets the color back to default

# Check for root
if [ "$(id -u)" != "0" ]; then
    echo "${RED}This script must be run as root or with sudo privileges${NC}"
    exit 1
fi

# Logging function
log() { 
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

# Run password changes
password_changes() {
    log "Changing passwords for default users..."
    for user in "${defaultUsers[@]}"; do
        log "Changing password for $user"
        echo "$user:$new_password" | chpasswd
        if [ $? -eq 0 ]; then
            log "${GREEN}Password changed for $user${NC}"
        else
            log "${RED}Failed to change password for $user${NC}"
            exit 1
        fi
    done
}

# Backup Splunk data
backup() {
    local BACKUP_DIR="/backup/splunk_$(date +%Y%m%d_%H%M%S)"
    local BACKUP_FILE="$BACKUP_DIR/splunk_backup.tar.gz"

    log "Creating backup of Splunk data..."
    mkdir -p "$BACKUP_DIR"
    tar -czvf "$BACKUP_FILE" \
        --exclude="$SPLUNK_HOME/var/run/splunk/dispatch" \
        --exclude="$SPLUNK_HOME/var/run/splunk/kvstore" \
        "$SPLUNK_HOME/etc" \
        "$SPLUNK_HOME/var/lib/splunk" \
        "$SPLUNK_HOME/var/log/splunk"
    if [ $? -eq 0 ]; then
        log "${GREEN}Backup created at $BACKUP_FILE${NC}"
        # Optional: SCP to backup server
        scp "$BACKUP_FILE" "$backup_account@$backupip:/backups/"
        [ $? -eq 0 ] && log "${GREEN}Backup sent to $backupip${NC}"
    else
        log "${RED}Backup failed${NC}"
        exit 1
    fi
}

# Update system and install security tools
updateinstall() {
    log "Updating system and installing security tools..."
    yum update -y || { log "${RED}System update failed${NC}"; exit 1; }
    yum install -y fail2ban rkhunter curl tripwire lynis audit
    systemctl enable fail2ban
    systemctl start fail2ban
    log "${GREEN}System updated and tools installed${NC}"
}

# Change SSH configuration
updateSSH() {
    local SSHD_CONFIG="/etc/ssh/sshd_config"
    log "Hardening SSH configuration..."
    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.backup"
    chmod 600 "$SSHD_CONFIG"

    sed -i \
      -e "s/^[# ]*Port.*/Port $SSH_PORT/" \
      -e 's/^[# ]*PasswordAuthentication.*/PasswordAuthentication no/' \
      -e 's/^[# ]*PermitRootLogin.*/PermitRootLogin no/' \
      -e 's/^[# ]*PubkeyAuthentication.*/PubkeyAuthentication yes/' \
      -e 's/^[# ]*X11Forwarding.*/X11Forwarding no/' \
      -e 's/^[# ]*MaxAuthTries.*/MaxAuthTries 3/' \
      -e 's/^[# ]*ClientAliveCountMax.*/ClientAliveCountMax 2/' \
      "$SSHD_CONFIG"

    if sshd -t; then
        systemctl restart sshd
        log "${GREEN}SSH hardened and restarted${NC}"
    else
        log "${RED}Invalid SSH configuration, rolling back${NC}"
        mv "${SSHD_CONFIG}.backup" "$SSHD_CONFIG"
        exit 1
    fi
}

# Configure firewall
firewallConfig() {
    log "Configuring firewall with firewalld..."
    firewall-cmd --new-zone=splunkzone --permanent
    firewall-cmd --set-default-zone=splunkzone
    for ip in $ALLOWED_IPS; do
        firewall-cmd --permanent --zone=splunkzone --add-source="$ip"
    done
    firewall-cmd --permanent --zone=splunkzone --add-port="$SSH_PORT/tcp"
    firewall-cmd --permanent --zone=splunkzone --add-port="$SPLUNK_WEB_PORT/tcp"
    firewall-cmd --permanent --zone=splunkzone --add-port="$SPLUNK_MGMT_PORT/tcp"
    firewall-cmd --permanent --zone=splunkzone --set-target=DROP
    firewall-cmd --reload
    log "${GREEN}Firewall configured:${NC}"
    firewall-cmd --list-all
}

# Harden Splunk-specific settings
hardenSplunk() {
    log "Hardening Splunk-specific settings..."
    chown -R splunk:splunk "$SPLUNK_HOME"
    chmod -R 750 "$SPLUNK_HOME"
    local WEB_CONF="$SPLUNK_HOME/etc/system/local/web.conf"
    echo -e "[settings]\nsslVersions = tls1.2\ncipherSuite = TLSv1.2:!eNULL:!aNULL" >> "$WEB_CONF"
    "$SPLUNK_HOME/bin/splunk" restart
    log "${GREEN}Splunk hardened and restarted${NC}"
}

# Install and run Lynis for hardening validation
runLynis() {
    log "Running Lynis audit..."
    lynis audit system --quick > /tmp/lynis_output 2>/dev/null
    local SCORE=$(grep "Hardening index" /tmp/lynis_output | awk '{print $4}' | tr -d '[]')
    log "Lynis Hardening Index: $SCORE"
    if [ "$SCORE" -lt 90 ]; then
        log "${YELLOW}Score below 90, consider additional hardening${NC}"
    else
        log "${GREEN}Lynis score satisfactory${NC}"
    fi
}

# Detect folder rename (splunk -> spunk)
detectRename() {
    log "Setting up auditd to detect folder rename (splunk -> spunk)..."
    echo "-w /opt -p wa -k splunk_rename" >> /etc/audit/rules.d/audit.rules
    auditctl -R /etc/audit/rules.d/audit.rules
    systemctl restart auditd

    # Background monitoring
    (
        while true; do
            LAST_EVENT=$(ausearch -k splunk_rename --format raw | tail -n 1)
            if [[ -n "$LAST_EVENT" && "$LAST_EVENT" =~ name=\"/opt/splunk\".*name=\"/opt/spunk\" ]]; then
                TIMESTAMP=$(echo "$LAST_EVENT" | grep -o 'time->[^ ]*' | cut -d'>' -f2)
                USER=$(echo "$LAST_EVENT" | grep -o 'auid=[0-9]*' | cut -d'=' -f2)
                log "${RED}[ALERT] Splunk folder renamed to spunk at $TIMESTAMP by user ID $USER${NC}"
            fi
            sleep 5
        done
    ) &
    log "${GREEN}Rename detection active in background${NC}"
}

# Main function
main() {
    log "Starting Splunk hardening process..."
    backup || { log "${RED}Backup failed, aborting${NC}"; exit 1; }
    password_changes || { log "${RED}Password changes failed${NC}"; exit 1; }
    updateinstall || { log "${RED}Update and install failed${NC}"; exit 1; }
    updateSSH || { log "${RED}SSH hardening failed${NC}"; exit 1; }
    firewallConfig || { log "${RED}Firewall config failed${NC}"; exit 1; }
    hardenSplunk || { log "${RED}Splunk hardening failed${NC}"; exit 1; }
    detectRename || { log "${RED}Rename detection setup failed${NC}"; exit 1; }
    runLynis || { log "${RED}Lynis audit failed${NC}"; exit 1; }
    log "${GREEN}Splunk hardening completed successfully${NC}"
}

# Execute main
main