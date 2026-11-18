#!/bin/bash
#
# This script installs PowerShell on Linux.
# It supports Debian/Ubuntu and RHEL/CentOS based distributions.
# This follows the official Microsoft installation guidelines.
#

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
fi

echo "--- Installing PowerShell for Linux ---"

# --- Detect Distribution ---
if [ -f /etc/debian_version ]; then
    DISTRO="debian"
    echo "[*] Detected Debian/Ubuntu based system."
elif [ -f /etc/redhat-release ]; then
    DISTRO="rhel"
    echo "[*] Detected RHEL/CentOS based system."
else
    echo "[-] Unsupported Linux distribution."
    exit 1
fi

# --- Installation for Debian/Ubuntu ---
if [ "$DISTRO" == "debian" ]; then
    # Install prerequisites
    apt-get update
    apt-get install -y wget apt-transport-https software-properties-common

    # Get the Ubuntu version
    source /etc/os-release
    
    # Download the Microsoft repository GPG keys
    wget -q "https://packages.microsoft.com/config/ubuntu/${VERSION_ID}/packages-microsoft-prod.deb"
    
    # Register the Microsoft repository GPG keys
    dpkg -i packages-microsoft-prod.deb
    
    # Update the list of products
    apt-get update
    
    # Install PowerShell
    apt-get install -y powershell

    # Clean up
    rm packages-microsoft-prod.deb

# --- Installation for RHEL/CentOS ---
elif [ "$DISTRO" == "rhel" ]; then
    # Register the Microsoft RedHat repository
    curl https://packages.microsoft.com/config/rhel/7/prod.repo | tee /etc/yum.repos.d/microsoft.repo

    # Install PowerShell
    yum install -y powershell
fi

# --- Verify Installation ---
if command -v pwsh &> /dev/null; then
    echo "[+] PowerShell installed successfully."
    pwsh -v
else
    echo "[-] PowerShell installation failed."
fi
