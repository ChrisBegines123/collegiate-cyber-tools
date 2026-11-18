#!/bin/bash

echo "[+] Installing rkhunter..."

# Detect OS
if [ -f /etc/debian_version ]; then
    sudo apt update -y
    sudo apt install rkhunter -y
elif [ -f /etc/redhat-release ]; then
    sudo yum install epel-release -y
    sudo yum install rkhunter -y
else
    echo "Unsupported OS"
    exit 1
fi

echo "[+] Updating rkhunter property database..."
sudo rkhunter --propupd

echo "[+] Updating signature files..."
sudo rkhunter --update

echo "[+] Creating config exception for /usr"
sudo sed -i 's/UPDATE_MIRRORS=0/UPDATE_MIRRORS=1/' /etc/rkhunter.conf
sudo sed -i 's/MIRRORS_MODE=1/MIRRORS_MODE=0/' /etc/rkhunter.conf
sudo sed -i 's/ALLOW_SSH_ROOT_USER=no/ALLOW_SSH_ROOT_USER=unset/' /etc/rkhunter.conf

echo "[+] Running full scan..."
sudo rkhunter -c --sk --rwo

echo ""
echo "Done! Check the logs:"
echo "/var/log/rkhunter.log"
