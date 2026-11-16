#!/usr/bin/env bash
# Author: Collin Dewey
# Description:
# Stuff that needs to get done right away. Only safe things, so no firewall.
# Usage:
# ./<Script_Name>

# Permission fix
chmod 755 /opt/ccdc
cd /opt/ccdc

# Kill SSH
if [ -f /usr/lib/systemd/system/sshd.service ] || [ -f /lib/systemd/system/sshd.service ]; then
    NAME=sshd
else
    NAME=ssh
fi

if systemctl is-active --quiet $NAME 2>/dev/null; then
    systemctl stop $NAME
fi

if ! systemctl is-enabled --quiet $NAME 2>/dev/null; then
    systemctl mask $NAME
fi

if pgrep sshd >/dev/null; then
    kill -9 $(pgrep sshd)
fi

# Setup users and passwords and junk (Hopefully safe)
/opt/ccdc/setup_users.sh

# Kernel settings (Safe)
/opt/ccdc/kernel_settings.sh

# Update certificates (I don't think this will break things?
/opt/ccdc/update_certificates.sh

# Dump info about the computer
/opt/ccdc/get_info.sh

# Misc
/opt/ccdc/misc_tweaks.sh

# Download pspy
/opt/ccdc/fetch_pspy.sh

# Syslog
/opt/ccdc/setup_syslog.sh 172.20.241.20

# Everything else is either dangerous or needs nix

# Get the user to sign in again
echo "Please login to the newly created ccdc user. Press enter"; read
exit 