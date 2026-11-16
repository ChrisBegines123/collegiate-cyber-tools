#!/usr/bin/env bash

set -euo pipefail

# Get list of users (who can log in)
users=$(cat /etc/passwd | grep -vE 'nologin|false' | awk -F: '$3 >= 1000 {print $1}')

# Get list of homedirs
homedirs=($(find /home -mindepth 1 -maxdepth 1 -type d))
homedirs_plus_root=("/root" "${homedirs[@]}")

# Disable startup_check.service if exists
# Do this first to prevent it from undoing changes later
if sudo systemctl is-active --quiet startup_check.service; then
    echo "Disabling startup_check.service..."
    sudo systemctl disable --now startup_check.service
else
    echo "startup_check.service not found or not active, skipping..."
fi

if sudo systemctl is-active --quiet startup_check-installer.service; then
    echo "Disabling startup_check-installer.service..."
    sudo systemctl disable --now startup_check-installer.service
else
    echo "startup_check-installer.service not found or not active, skipping..."
fi

# Disable tailscale if exists
if sudo systemctl is-active --quiet tailscaled; then
    echo "Disabling Tailscale service..."
    sudo systemctl disable --now tailscaled
else
    echo "Tailscale service not found or not active, skipping..."
fi

# Check for SSH authorized_keys
for dir in "${homedirs_plus_root[@]}"; do
    if [ -f "$dir/.ssh/authorized_keys" ]; then
        echo "Disabling authorized_keys for $dir"
        mv "$dir/.ssh/authorized_keys" "$dir/.ssh/authorized_keys.disabled"
    else
        echo "No authorized_keys found for $dir, skipping..."
    fi
done

# Check for SSH private keys
for dir in "${homedirs_plus_root[@]}"; do
    if [ -f "$dir/.ssh/id_rsa" ]; then
        echo "Deleting SSH private key for $dir"
        rm -f "$dir/.ssh/id_rsa"
    else
        echo "No SSH private key found for $dir, skipping..."
    fi
done

# Change root, sysadmin password
# Prompt user for new password
echo "Enter new password for root:"
read root_passwd

echo "Enter new password for sysadmin:"
read sysadmin_passwd

echo "Changing root password to: $root_passwd"
echo "Changing sysadmin password to: $sysadmin_passwd"

echo "root:$root_passwd" | sudo chpasswd
echo "sysadmin:$sysadmin_passwd" | sudo chpasswd

# Back up passwords in case bro forgot to pipe the output of this script to a file
echo "root:$root_passwd" | sudo tee -a /tmp/feetpics.txt
echo "sysadmin:$sysadmin_passwd" | sudo tee -a /tmp/feetpics.txt

echo "============================================================================"
echo "===== IMPORTANT: Delete /tmp/feetpics.txt after noting down passwords! ====="
echo "============================================================================"
