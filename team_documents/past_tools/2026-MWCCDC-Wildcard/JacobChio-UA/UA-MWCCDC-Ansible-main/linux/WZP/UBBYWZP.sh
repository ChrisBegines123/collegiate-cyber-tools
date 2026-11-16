#!/bin/bash

set -e

# ==========================================
# Wazuh Agent Auto Installer for Ubuntu 24.04
# ==========================================

MANAGER_IP="${1:-10.0.0.5}"

echo "[+] Starting Wazuh agent installation"
echo "[+] Manager IP: $MANAGER_IP"

# -------------------------
# Robust Ubuntu 24.04 check
# -------------------------
OS_VERSION=$(grep VERSION_ID /etc/os-release | cut -d '"' -f2)

if [[ "$OS_VERSION" != 24.04* ]]; then
    echo "[!] This script is intended for Ubuntu 24.04"
    echo "[!] Detected VERSION_ID: $OS_VERSION"
    exit 1
fi

echo "[+] Ubuntu 24.04 detected"

# -------------------------
# Update and install deps
# -------------------------
echo "[+] Updating apt"
sudo apt update -y

echo "[+] Installing required packages"
sudo apt install -y curl gnupg apt-transport-https lsb-release

# -------------------------
# Add Wazuh repo
# -------------------------
echo "[+] Adding Wazuh GPG key"
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH \
  | sudo gpg --dearmor -o /usr/share/keyrings/wazuh.gpg

echo "[+] Adding Wazuh repository"
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
  | sudo tee /etc/apt/sources.list.d/wazuh.list

sudo apt update -y

# -------------------------
# Install Wazuh agent
# -------------------------
echo "[+] Installing Wazuh agent"
sudo apt install -y wazuh-agent

# -------------------------
# Configure manager IP
# -------------------------
echo "[+] Configuring manager IP"
sudo sed -i "s|<address>.*</address>|<address>$MANAGER_IP</address>|" \
  /var/ossec/etc/ossec.conf

# -------------------------
# Enable and start service
# -------------------------
echo "[+] Enabling and starting wazuh-agent"
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl restart wazuh-agent

# -------------------------
# Verify
# -------------------------
echo "[+] Checking service status"
sudo systemctl status wazuh-agent --no-pager

echo "[+] Wazuh agent installation complete on Ubuntu 24.04"


