#!/usr/bin/env bash
# Description:
# Disables the firewall
# Usage:
# ./<SCRIPT NAME>
# 

# Variables
. $(dirname "$0")/helper.sh; if [ -z ${PUBLIC_KEY+x} ]; then exit 1; fi
root_check

if [ -f "/usr/sbin/iptables-nft" ]; then # Oh no
    shopt -s expand_aliases
    alias iptables=/usr/sbin/iptables-nft
    alias iptables-save=/usr/sbin/iptables-nft-save
    alias ip6tables=/usr/sbin/ip6tables-nft
    alias ip6tables-save=/usr/sbin/ip6tables-nft-save
fi

# Reset IPv4
table_names=$(iptables-save | grep '^*' | sed 's/*//g' | sort | uniq)
for table_name in $table_names
do
  iptables -t $table_name -F
  iptables -t $table_name -X
done
iptables -F
iptables -X
iptables -Z
iptables -P FORWARD DROP
iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT