#!/usr/bin/env nix
#! nix shell nixpkgs#bash nixpkgs#bind --command bash
# Author: Collin Dewey
# Description:
# Bind9 SystemD Override
# Usage:
# ./<Script_Name>

. $(dirname "$0")/helper.sh; if [ -z ${PUBLIC_KEY+x} ]; then exit 1; fi
root_check

if [ -f /lib/systemd/system/bind9.service ]; then
    systemctl stop bind9
    mkdir -p /etc/systemd/system/bind9.service.d
    echo "[Service]
    Type=simple
    ExecStart=
    ExecStart=$(which named) -c /etc/bind/named.conf -4 -f -u bind
    ExecReload=
    ExecReload=$(which rndc) reload
    ExecStop=
    ExecStop=$(which rndc) stop
    Group=dns_in" >> /etc/systemd/system/bind9.service.d/override.conf
    systemctl daemon-reload
    systemctl start bind9
fi