#!/bin/bash
echo "Running IPTables Script from:"
pwd
echo "Backups Will BE HERE^^"
sleep 1
iptables-save > ./b4script.iptables.bck
#FLUSH and REMOVE ALL RULES:
iptables -F
iptables -X
iptables -Z
#
# IPv6 DROP POLICY
ip6tables -P INPUT DROP
ip6tables -P OUTPUT DROP
ip6tables -P FORWARD DROP
#
# Allow loopback traffic
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT
#
# OPEN INBOUND UNLIMITED:
#INPUT [UDP] -Dest/Source Ports
iptables -A INPUT -p udp --match multiport --dports 53,123 -j ACCEPT
iptables -A INPUT -p udp --match multiport --sports 53,123 -j ACCEPT
#INPUT [TCP] -Dest/Source Ports
iptables -A INPUT -p tcp --match multiport --dports 53,80,8000,8089,9997 -j ACCEPT
iptables -A INPUT -p tcp --match multiport --sports 53,80,8000,8089,9997 -j ACCEPT
#
# DoS PREVENTION
#Ping DoS:
iptables -A INPUT -p icmp -m limit --limit 1/second --limit-burst 1 -j ACCEPT
#General IPTables TCP Rate Limiting
iptables -A INPUT -p tcp -m recent --set
iptables -A INPUT -p tcp -m state --state NEW -m recent --update --seconds 3 --hitcount 150 -j DROP
#
# OPEN OUTBOUND
iptables -A OUTPUT -p udp --match multiport --dports 53,123 -j ACCEPT
iptables -A OUTPUT -p udp --match multiport --sports 53,123 -j ACCEPT
#
iptables -A OUTPUT -p tcp --match multiport --dports 53,80,8000,8089,9997 -j ACCEPT
iptables -A OUTPUT -p tcp --match multiport --sports 53,80,8000,8089,9997 -j ACCEPT
iptables -A OUTPUT -p icmp -j ACCEPT
#
# IPv4 DROP POLICY
iptables -P FORWARD DROP
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables-save > ./my.iptables.bck
#
#
if ! grep -q "net.ipv6.conf.all.disable_ipv6 = 1" /etc/sysctl.conf; then
  echo "#Disable IPv6
  net.ipv6.conf.all.disable_ipv6 = 1
  net.ipv6.conf.default.disable_ipv6 = 1
  net.ipv6.conf.lo.disable_ipv6 = 1" >> /etc/sysctl.conf  
  sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
  sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
  sleep 1
fi
#
iptables -L
