#!/bin/bash
#
# This script configures the firewall using ufw.
# It sets up a basic secure configuration, denying incoming
# traffic by default and allowing specific services.
#

# Check if ufw is installed
if ! command -v ufw &> /dev/null; then
    echo "ufw is not installed. Please install it first."
    echo "For Debian/Ubuntu: sudo apt-get install ufw"
    exit 1
fi

echo "--- Configuring Firewall (ufw) ---"

# Reset ufw to default settings
echo "[*] Resetting ufw to default settings..."
yes | ufw reset

# Set default policies
echo "[*] Setting default policies..."
ufw default deny incoming
ufw default allow outgoing
echo "[+] Default incoming policy set to deny."
echo "[+] Default outgoing policy set to allow."

# Allow essential services
# It's crucial to allow SSH before enabling the firewall,
# otherwise you might get locked out.
echo "[*] Allowing essential services..."
ufw allow ssh # Port 22
ufw allow http # Port 80
ufw allow https # Port 443
echo "[+] Allowed SSH, HTTP, and HTTPS."

# You can add more rules here for other services.
# For example:
# ufw allow 8080/tcp # Allow custom web port
# ufw allow from 192.168.1.0/24 to any port 3306 # Allow MySQL from a specific subnet

# Enable logging
echo "[*] Enabling logging..."
ufw logging on

# Enable the firewall
echo "[*] Enabling the firewall..."
yes | ufw enable

# Display firewall status
echo "[*] Firewall status:"
ufw status verbose

echo "--- Firewall configuration complete ---"
