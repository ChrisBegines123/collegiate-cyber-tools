#!/bin/bash

# Advanced Splunk Server Hardening Script with Lynis
# Date: March 04, 2025
# Goal: Achieve Lynis score ~100 while keeping Splunk functional

# Variables
SPLUNK_HOME="/opt/splunk"
SPLUNK_USER="admin"
ALLOWED_IPS="192.168.1.0/24"  # Customize for your network
SSH_PORT=22
SPLUNK_WEB_PORT=8000
SPLUNK_MGMT_PORT=8089
LOG_FILE="/var/log/splunk_lynis_hardening.log"
LYNIS_REPO="https://packages.cisofy.com/community/lynis/deb/"
LYNIS_SCORE_TARGET=95  # Realistic target (100 is often impractical)
BACKUP_DIR="/root/backup_$(date +%Y%m%d_%H%M%S)"
ITERATION_LIMIT=5

# Ensure root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Log all actions
exec > >(tee -a "$LOG_FILE") 2>&1
echo "Splunk Lynis Hardening Script - Started at $(date)"

# Function to check command success
check_status() {
    if [ $? -eq 0 ]; then
        echo "[SUCCESS] $1"
    else
        echo "[FAILURE] $1 - Check $LOG_FILE for details"
        exit 1
    fi
}

# Function to backup critical files
backup_files() {
    mkdir -p "$BACKUP_DIR"
    cp -r /etc/ssh/sshd_config "$BACKUP_DIR/"
    cp -r /etc/sysctl.conf "$BACKUP_DIR/"
    cp -r "$SPLUNK_HOME/etc/system/local" "$BACKUP_DIR/splunk_configs" 2>/dev/null
    check_status "Backup of critical files to $BACKUP_DIR"
}

# Function to install Lynis
install_lynis() {
    echo "Installing Lynis..."
    if [ -f /etc/redhat-release ]; then
        yum install -y epel-release
        yum install -y lynis
    elif [ -f /etc/debian_version ]; then
        apt update
        apt install -y apt-transport-https wget gnupg2
        wget -O - https://packages.cisofy.com/keys/cisofy-software-public.key | apt-key add -
        echo "deb $LYNIS_REPO stable main" > /etc/apt/sources.list.d/cisofy-lynis.list
        apt update
        apt install -y lynis
    fi
    lynis update info
    check_status "Lynis installation"
}

# Function to get current Lynis hardening score
get_lynis_score() {
    lynis audit system --quick > /tmp/lynis_output 2>/dev/null
    SCORE=$(grep "Hardening index" /tmp/lynis_output | awk '{print $4}' | tr -d '[]')
    echo "Current Lynis Hardening Index: $SCORE"
    return "$SCORE"
}

# Function to apply hardening based on Lynis suggestions
harden_system() {
    echo "Applying hardening based on Lynis suggestions..."

    # Parse Lynis output for common suggestions/warnings
    LYNIS_LOG="/var/log/lynis.log"
    LYNIS_REPORT="/var/log/lynis-report.dat"

    # SSH Hardening
    if grep -q "SSH-7408" "$LYNIS_LOG"; then
        sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
        sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
        systemctl restart sshd
        check_status "SSH hardening"
    fi

    # Kernel Hardening (sysctl)
    if grep -q "KRNL-6000" "$LYNIS_LOG"; then
        cat >> /etc/sysctl.conf <<EOF
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.ip_forward = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
kernel.randomize_va_space = 2
fs.suid_dumpable = 0
EOF
        sysctl -p
        check_status "Kernel hardening"
    fi

    # File Permissions
    if grep -q "FILE-6310" "$LYNIS_LOG"; then
        chmod 640 /etc/passwd /etc/shadow /etc/group
        chown root:root /etc/passwd /etc/shadow /etc/group
        check_status "File permissions hardening"
    fi

    # Disable unused services
    if grep -q "SRV-5040" "$LYNIS_LOG"; then
        systemctl disable rpcbind postfix 2>/dev/null
        check_status "Disabled unnecessary services"
    fi

    # Firewall rules (iptables example)
    if grep -q "FIRE-4510" "$LYNIS_LOG"; then
        iptables -F
        iptables -P INPUT DROP
        iptables -P FORWARD DROP
        iptables -P OUTPUT ACCEPT
        iptables -A INPUT -i lo -j ACCEPT
        for ip in $ALLOWED_IPS; do
            iptables -A INPUT -s "$ip" -p tcp --dport "$SSH_PORT" -j ACCEPT
            iptables -A INPUT -s "$ip" -p tcp --dport "$SPLUNK_WEB_PORT" -j ACCEPT
            iptables -A INPUT -s "$ip" -p tcp --dport "$SPLUNK_MGMT_PORT" -j ACCEPT
        done
        iptables-save > /etc/sysconfig/iptables
        check_status "Firewall rules applied"
    fi

    # Splunk-specific hardening
    chown -R "$SPLUNK_USER":"$SPLUNK_USER" "$SPLUNK_HOME"
    chmod -R 750 "$SPLUNK_HOME"
    sed -i '/\[settings\]/a sslVersions = tls1.2\ncipherSuite = TLSv1.2:!eNULL:!aNULL' "$SPLUNK_HOME/etc/system/local/web.conf"
    "$SPLUNK_HOME/bin/splunk" restart
    check_status "Splunk-specific hardening"
}

# Main execution
echo "Starting hardening process..."

# Backup critical files
backup_files

# Install Lynis if not present
if ! command -v lynis >/dev/null 2>&1; then
    install_lynis
fi

# Initial audit
get_lynis_score
INITIAL_SCORE=$?

# Iterative hardening
ITERATION=1
CURRENT_SCORE=$INITIAL_SCORE

while [ "$CURRENT_SCORE" -lt "$LYNIS_SCORE_TARGET" ] && [ "$ITERATION" -le "$ITERATION_LIMIT" ]; do
    echo "Iteration $ITERATION: Hardening system (Score: $CURRENT_SCORE)"
    harden_system
    get_lynis_score
    CURRENT_SCORE=$?
    ((ITERATION++))
done

# Final audit and report
echo "Final Lynis Audit..."
lynis audit system --quick > /tmp/lynis_final_output
FINAL_SCORE=$(grep "Hardening index" /tmp/lynis_final_output | awk '{print $4}' | tr -d '[]')
echo "Final Lynis Hardening Index: $FINAL_SCORE"
cat /tmp/lynis_final_output >> "$LOG_FILE"

if [ "$FINAL_SCORE" -ge "$LYNIS_SCORE_TARGET" ]; then
    echo "[SUCCESS] Achieved target score of $LYNIS_SCORE_TARGET or higher!"
else
    echo "[WARNING] Final score ($FINAL_SCORE) below target ($LYNIS_SCORE_TARGET). Review $LOG_FILE for remaining issues."
fi

echo "Hardening process completed at $(date)"
exit 0