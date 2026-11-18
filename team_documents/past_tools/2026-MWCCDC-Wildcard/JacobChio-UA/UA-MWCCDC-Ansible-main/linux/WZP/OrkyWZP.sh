
#!/bin/bash

set -e

# ==========================================
# Wazuh Manager Installation for Oracle Linux 9
# Central log collection and analysis server
# ==========================================

echo "[+] Starting Wazuh Manager installation for Oracle Linux 9"

# -------------------------
# Robust Oracle Linux 9 check
# -------------------------
if [ -f /etc/os-release ]; then
	OS_ID=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
	OS_VERSION=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
else
	echo "[!] /etc/os-release not found; cannot detect OS"
	exit 1
fi

# Accept common Oracle Linux identifiers: "ol" or "oracle"
if { [[ "$OS_ID" != ol ]] && [[ "$OS_ID" != oracle ]]; } || [[ "$OS_VERSION" != 9* ]]; then
	echo "[!] This script is intended for Oracle Linux 9"
	echo "[!] Detected: ID=$OS_ID VERSION_ID=$OS_VERSION"
	exit 1
fi

echo "[+] Oracle Linux 9 detected - installing Wazuh Manager"

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
# Install Wazuh Manager (NOT agent)
# -------------------------
echo "[+] Installing Wazuh Manager"
sudo dnf install -y wazuh-manager

# -------------------------
# Enable and start Wazuh Manager service
# -------------------------
echo "[+] Enabling and starting wazuh-manager"
sudo systemctl daemon-reload
sudo systemctl enable --now wazuh-manager

# -------------------------
# Verify Manager is running
# -------------------------
echo "[+] Checking Wazuh Manager service status"
sudo systemctl status wazuh-manager --no-pager

# -------------------------
# Display manager info
# -------------------------
echo ""
echo "[+] =========================================="
echo "[+] Wazuh Manager Installation Complete"
echo "[+] =========================================="
echo "[+] Manager is listening on:"
echo "[+]   - Agent connection port: 1514 (TCP)"
echo "[+]   - Manager API port: 55000 (HTTPS)"
echo "[+]"
echo "[+] Next steps:"
echo "[+] 1. Add firewall rules to allow agent connections (port 1514)"
echo "[+] 2. Deploy Wazuh agents on other machines with this manager's IP"
echo "[+] 3. Access Wazuh Dashboard for log analysis"
echo "[+] =========================================="

