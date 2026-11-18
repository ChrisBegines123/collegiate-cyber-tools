#!/bin/bash

# Define the ports and protocols you want to allow

ALLOWED_PORTS=("25/tcp" "53/tcp" "110/tcp" "143/tcp" "587/tcp" "995/tcp")

# The location of the iptables program
IPTABLES=/sbin/iptables

echo "Configuring iptables to allow only specific ports..."

# 1. Flush all existing rules and delete all non-default chains
$IPTABLES -F
$IPTABLES -X
echo "Existing rules flushed."


$IPTABLES -P INPUT DROP
$IPTABLES -P FORWARD DROP

$IPTABLES -P OUTPUT ACCEPT
echo "Default policies set to DROP for INPUT/FORWARD, ACCEPT for OUTPUT."

$IPTABLES -A INPUT -i lo -j ACCEPT
$IPTABLES -A OUTPUT -o lo -j ACCEPT
echo "Loopback traffic allowed."

# 5. Explicitly allow the specific incoming ports defined above
for port_proto in "${ALLOWED_PORTS[@]}"; do
    PORT=$(echo $port_proto | cut -d'/' -f1)
    PROTO=$(echo $port_proto | cut -d'/' -f2)
    $IPTABLES -A INPUT -p $PROTO --dport $PORT -j ACCEPT
    echo "Allowed incoming port $PORT/$PROTO."
done

$systemctl stop firewalld
$systemctl mask firewalld
$systemctl start iptables
$systemctl status iptables


/sbin/iptables-save > /etc/sysconfig/iptables
echo "Iptables rules saved (check /etc/sysconfig/iptables file for verification/persistence)."

echo "Iptables configuration complete."