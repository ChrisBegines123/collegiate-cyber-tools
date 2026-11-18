#!/bin/bash
#------------------------------------------------------------
# Splunk Enterprise Installation Script
#------------------------------------------------------------
# This script installs and configures Splunk Enterprise on Linux
#------------------------------------------------------------

# Exit immediately if a command fails
set -e

# -------------------------
# Configuration Variables
# -------------------------
SPLUNK_RPM_URL="https://download.splunk.com/products/splunk/releases/9.1.1/linux/splunk-9.1.1-64e843ea36b1.x86_64.rpm"
SPLUNK_RPM_FILE="splunk-9.1.1-64e843ea36b1.x86_64.rpm"
SPLUNK_HOME="/opt/splunk"

SPLUNK_SYSTEM_USER="splunk"
SPLUNK_SYSTEM_PASS="password"    # Linux login password for the splunk user

# -------------------------
# 1. Create splunk system user
# -------------------------
if ! id -u "$SPLUNK_SYSTEM_USER" >/dev/null 2>&1; then
    echo "Creating Splunk system user '$SPLUNK_SYSTEM_USER' with login shell..."
    sudo useradd -m -d "$SPLUNK_HOME" -s /bin/bash "$SPLUNK_SYSTEM_USER"
    echo "$SPLUNK_SYSTEM_USER:$SPLUNK_SYSTEM_PASS" | sudo chpasswd
fi

# -------------------------
# 2. Download Splunk RPM
# -------------------------
echo "Downloading Splunk RPM..."
wget -O "$SPLUNK_RPM_FILE" "$SPLUNK_RPM_URL"

# -------------------------
# 3. Install Splunk RPM
# -------------------------
echo "Installing Splunk..."
sudo rpm -i "$SPLUNK_RPM_FILE"

# -------------------------
# 4. Set ownership
# -------------------------
echo "Setting ownership of $SPLUNK_HOME to $SPLUNK_SYSTEM_USER..."
sudo chown -R "$SPLUNK_SYSTEM_USER":"$SPLUNK_SYSTEM_USER" "$SPLUNK_HOME"

# -------------------------
# 5. Start Splunk first time
# -------------------------
echo "Starting Splunk for the first time (accepting license)..."
sudo -u "$SPLUNK_SYSTEM_USER" "$SPLUNK_HOME/bin/splunk" start --accept-license --answer-yes --no-prompt

echo "Enabling Splunk to start at boot..."
sudo "$SPLUNK_HOME/bin/splunk" enable boot-start --user "$SPLUNK_SYSTEM_USER" --accept-license --answer-yes --no-prompt

# -------------------------
# 6. Open firewall ports
# -------------------------
echo "Opening firewall ports 8089 and 9997..."
if command -v firewall-cmd >/dev/null 2>&1; then
    sudo firewall-cmd --permanent --add-port=8089/tcp
    sudo firewall-cmd --permanent --add-port=9997/tcp
    sudo firewall-cmd --reload
else
    echo "Warning: firewall-cmd not found. Please open ports 8089 and 9997 manually."
fi

# -------------------------
# Done
# -------------------------
echo "Splunk installation and configuration complete."
echo "Linux system user: $SPLUNK_SYSTEM_USER (password: $SPLUNK_SYSTEM_PASS)"
