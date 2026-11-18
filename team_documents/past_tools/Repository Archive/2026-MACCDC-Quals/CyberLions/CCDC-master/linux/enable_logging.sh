#!/bin/bash
#
# This script enables and configures detailed system logging using auditd
# and ensures rsyslog is running. This is crucial for monitoring and
# incident response during CCDC.
#

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
fi

echo "--- Enabling and Configuring System Logging ---"

# --- Configure auditd ---
echo "[*] Installing and configuring auditd..."

# Install auditd if not present
if ! command -v auditd &> /dev/null; then
    echo "auditd not found. Installing..."
    if command -v apt-get &> /dev/null; then
        apt-get update
        apt-get install -y auditd audispd-plugins
    elif command -v yum &> /dev/null; then
        yum install -y audit audit-libs
    else
        echo "[-] Cannot determine package manager. Please install auditd manually."
        exit 1
    fi
fi

# Start and enable the auditd service
systemctl enable auditd
systemctl start auditd

# Define the audit rules file
# A comprehensive ruleset can be quite large. We will add some common rules.
# For CCDC, it's a good idea to have a pre-made, more extensive ruleset.
# This script will add some baseline rules.
AUDIT_RULES_FILE="/etc/audit/rules.d/ccdc-audit.rules"
echo "[*] Adding baseline audit rules to ${AUDIT_RULES_FILE}..."

# Rules to monitor important files
cat > "${AUDIT_RULES_FILE}" <<EOL
# --- CCDC Baseline Audit Rules ---

# Monitor changes to important system files
-w /etc/passwd -p wa -k passwd_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/group -p wa -k group_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/ssh/sshd_config -p wa -k sshd_config_changes

# Monitor critical system binaries for execution
-w /bin/mount -p x -k mount_binary
-w /usr/bin/passwd -p x -k passwd_binary
-w /usr/bin/chsh -p x -k chsh_binary

# Monitor for use of privilege escalation commands
-w /bin/su -p x -k su_binary
-w /usr/bin/sudo -p x -k sudo_binary

# Monitor syscalls related to module loading
-a always,exit -F arch=b64 -S init_module -S delete_module -k module_changes
-a always,exit -F arch=b32 -S init_module -S delete_module -k module_changes

# Make the audit configuration immutable (optional, but good for CCDC)
# This prevents the rules from being changed until the next reboot.
# -e 2
EOL

# Reload auditd to apply the new rules
echo "[*] Reloading auditd to apply new rules..."
augenrules --load

echo "[+] auditd configured and rules loaded."

# --- Configure rsyslog ---
echo "[*] Ensuring rsyslog is running..."

# Start and enable the rsyslog service
if command -v systemctl &> /dev/null; then
    systemctl enable rsyslog
    systemctl start rsyslog
    echo "[+] rsyslog service is enabled and running."
else
    echo "[-] Could not manage rsyslog with systemctl. Please ensure it is running."
fi

# We can also add custom rsyslog configurations, for example, to forward
# logs to a remote server. For this script, we'll just ensure it's running.

echo "--- System logging configuration complete ---"
