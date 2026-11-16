#!/bin/bash

set -e

# ==========================================
# Wazuh Agent Auto Installer for Fedora 42
# ==========================================

MANAGER_IP="${1:-10.0.0.5}"

echo "[+] Starting Wazuh agent installation"
echo "[+] Manager IP: $MANAGER_IP"

# -------------------------
# Robust Fedora 42 check
# -------------------------
if [ -f /etc/os-release ]; then
	OS_ID=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
	OS_VERSION=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
else
	echo "[!] /etc/os-release not found; cannot detect OS"
	exit 1
fi

if [[ "$OS_ID" != fedora || "$OS_VERSION" != 42* ]]; then
	echo "[!] This script is intended for Fedora 42"
	echo "[!] Detected: ID=$OS_ID VERSION_ID=$OS_VERSION"
	exit 1
fi

echo "[+] Fedora 42 detected"

# -------------------------
# Update and install deps
# -------------------------
echo "[+] Updating dnf"
sudo dnf -y makecache --refresh

echo "[+] Installing required packages"
sudo dnf install -y curl gnupg2 ca-certificates

# -------------------------
# Add Wazuh repo
# -------------------------
echo "[+] Importing Wazuh GPG key"
sudo rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH

echo "[+] Adding Wazuh repository"
sudo tee /etc/yum.repos.d/wazuh.repo > /dev/null <<'REPO'
[wazuh]
name=Wazuh repository
baseurl=https://packages.wazuh.com/4.x/yum/
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
REPO

sudo dnf -y makecache

# -------------------------
# Install Wazuh agent
# -------------------------
echo "[+] Installing Wazuh agent"
sudo dnf install -y wazuh-agent

# -------------------------
# Configure manager IP
# -------------------------
if [ -f /var/ossec/etc/ossec.conf ]; then
	echo "[+] Configuring manager IP"
	sudo sed -i "s|<address>.*</address>|<address>$MANAGER_IP</address>|" /var/ossec/etc/ossec.conf
else
	echo "[!] ossec.conf not found at /var/ossec/etc/ossec.conf"
fi

# -------------------------
# Enable and start service
# -------------------------
echo "[+] Enabling and starting wazuh-agent"
sudo systemctl daemon-reload
sudo systemctl enable --now wazuh-agent

# -------------------------
# Verify
# -------------------------
echo "[+] Checking service status"
sudo systemctl status wazuh-agent --no-pager

echo "[+] Wazuh agent installation complete on Fedora 42"

