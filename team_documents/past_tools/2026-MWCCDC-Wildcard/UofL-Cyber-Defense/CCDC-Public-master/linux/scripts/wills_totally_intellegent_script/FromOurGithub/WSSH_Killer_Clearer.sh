#!/bin/bash

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
#-----
#Clear old SSH Keys (modified Collin's work)
#-----
 for user in /home/*; do rm -f "$user/.ssh/authorized_keys"; done
rm -f /root/.ssh/authorized_keys
# In case deleting the root key folder errors, use "chattr -i" and try again
chattr -i /root/.ssh/authorized_keys
#-----
