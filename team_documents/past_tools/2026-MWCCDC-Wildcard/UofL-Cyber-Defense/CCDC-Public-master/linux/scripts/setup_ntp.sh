#!/usr/bin/env bash
# Author: Collin Dewey
# Description:
# Configures timesyncd/chrony/NTPd
# Usage:
# ./<Script_Name> <NTP_SERVER>

. $(dirname "$0")/helper.sh; if [ -z ${PUBLIC_KEY+x} ]; then exit 1; fi
root_check

if [ $# -ne 1 ]; then
    echo "Usage: $0 <NTP_SERVER>"
    exit 1
fi

if [ -f "/etc/systemd/timesyncd.conf" ]; then
    mkdir -p /etc/systemd/timesyncd.conf.d
    echo "NTP=$1" >> /etc/systemd/timesyncd.conf.d/server.conf
    timedatectl set-ntp true
    systemctl restart systemd-timesyncd
    echo "systemd-timesyncd"
    exit 1
fi

if [ -f "/etc/chrony.conf" ]; then
    mv /etc/chrony.conf /etc/chrony.conf.old
    echo "server $1 iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
keyfile /etc/chrony.keys
leapsectz right/UTC
logdir /var/log/chrony" > /etc/chrony.conf
    systemctl restart chronyd
    echo "chronyd"
    exit 1
fi

if command -v ntp >/dev/null 2>&1 || command -v ntpd >/dev/null 2>&1; then
    echo "ntpd"
else
    if command -v apt-get >/dev/null 2>&1; then
        DEBIAN_FRONTEND="noninteractive" web apt-get update -y
        DEBIAN_FRONTEND="noninteractive" web apt-get install ntp -y
    elif command -v yum >/dev/null 2>&1; then
        web yum install -y ntp
    else
        echo "Insomnia"
        exit 1
    fi
fi
sed -i 's/^server/#&/' /etc/ntp.conf
echo "server $1" >> /etc/ntp.conf