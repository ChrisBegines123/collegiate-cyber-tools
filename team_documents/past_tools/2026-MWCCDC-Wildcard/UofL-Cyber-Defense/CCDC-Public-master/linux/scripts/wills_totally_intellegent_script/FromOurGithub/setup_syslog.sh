#!/usr/bin/env bash
# Author: Collin Dewey
# Description:
# Forwards logs using rsyslog to a specified address
# Usage: 
# ./<Script_Name> <IP>

. $(dirname "$0")/helper.sh; if [ -z ${PUBLIC_KEY+x} ]; then exit 1; fi
root_check

IP_ADDR="$1"

echo "
*.* @$IP_ADDR:514
*.* @@$IP_ADDR:514
" >> /etc/rsyslog.conf

if [ -f /etc/systemd/journald.conf ]; then
    echo "ForwardToSyslog=yes" >> /etc/systemd/journald.conf
    systemctl restart systemd-journald
fi

systemctl restart rsyslog