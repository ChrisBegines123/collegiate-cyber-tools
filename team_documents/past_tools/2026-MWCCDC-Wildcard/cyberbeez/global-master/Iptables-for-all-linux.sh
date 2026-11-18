#!/bin/bash

echo "Enter the ports that you want to be open in the format 53,123,443 DO NOT PUT SPACES"
echo "The ports that are open are 123,8089,9997 both inbound and outbound"
read -p "Enter the inbound UDP ports you want open: " udpInbound;
read -p "Enter the outbound UDP port you want open: " udpOutboud;
read -p "Enter the inbound TCP port you want open: " tcpinbound;
read -p "Enter the outbound TCP ports you want open: " tcpOutbound;



cd ~
iptables-save > ./default.iptables.bck
iptables -F
ip6tables -P INPUT DROP
ip6tables -P OUTPUT DROP
ip6tables -P FORWARD DROP
iptables -A INPUT -f -j DROP
iptables -A INPUT -p tcp ! --tcp-flags SYN,ACK SYN -m state --state NEW -j DROP
iptables -A INPUT -p udp --match multiport --dports 123,$udpInbound -j ACCEPT
iptables -A INPUT -p udp --match multiport --sports 123,$udpInbound -j ACCEPT
iptables -A INPUT -p tcp --match multiport --dports 8089,9997,$tcpinbound -j ACCEPT
iptables -A INPUT -p tcp --match multiport --sports 8089,9997,$tcpinbound -j ACCEPT
iptables -A INPUT -p icmp -j ACCEPT
iptables -A OUTPUT -f -j DROP
iptables -A OUTPUT -p tcp ! --tcp-flags SYN,ACK SYN -m state --state NEW -j DROP
iptables -A OUTPUT -p udp --match multiport --dports 123,$udpOutboud -j ACCEPT
iptables -A OUTPUT -p udp --match multiport --sports 123,$udpOutboud -j ACCEPT
iptables -A OUTPUT -p tcp --match multiport --dports 8089,9997,$tcpOutbound -j ACCEPT
iptables -A OUTPUT -p tcp --match multiport --sports 8089,9997,$tcpOutbound -j ACCEPT
iptables -A OUTPUT -p icmp -j ACCEPT
iptables -A INPUT -p icmp -j ACCEPT
iptables -P FORWARD DROP
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables-save > /var/my.iptables.bck

if ! grep -q "net.ipv6.conf.all.disable_ipv6 = 1" /etc/sysctl.conf; then
  echo "#Disable IPv6
  net.ipv6.conf.all.disable_ipv6 = 1
  net.ipv6.conf.default.disable_ipv6 = 1
  net.ipv6.conf.lo.disable_ipv6 = 1" >> /etc/sysctl.conf  
  service procps restart
  service procps status 
  sleep 10
fi

iptables -L
