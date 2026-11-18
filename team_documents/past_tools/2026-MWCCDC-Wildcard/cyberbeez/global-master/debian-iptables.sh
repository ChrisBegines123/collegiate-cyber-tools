#!/bin/bash
cd ..
iptables-save > ~/default.iptables.bck
iptables -F
ip6tables -P INPUT DROP
ip6tables -P OUTPUT DROP
ip6tables -P FORWARD DROP
iptables -A INPUT -f -j DROP
iptables -A INPUT -p udp --match multiport --dports 53 -j ACCEPT
iptables -A INPUT -p tcp --match multiport --dports 53 -j ACCEPT
iptables -A INPUT -p udp --match multiport --dports 123 -j ACCEPT
iptables -A INPUT -p udp --match multiport --sports 123 -j ACCEPT
iptables -A INPUT -p tcp ! --tcp-flags SYN,ACK SYN -m state --state NEW -j DROP
iptables -A INPUT -p udp -m state NEW -m recent --set --name DEFAULT --mask 255.255.255.255 --rsource -j DROP
iptables -A INPUT -p udp -m state NEW -m recent --update -- seconds 10 --hitcound 20 --name DEFAULT --mask 255.255.255.255 --rsoure
iptables -A INPUT -p tcp -m state NEW -m recent --set --name DEFAULT --mask 255.255.255.255 --rsource -j DROP
iptables -A INPUT -p tcp -m state NEW -m recent --update -- seconds 10 --hitcound 20 --name DEFAULT --mask 255.255.255.255 --rsoure
iptables -A INPUT -p tcp --match multiport --dports 80,443,8089,9997 -j ACCEPT
iptables -A INPUT -p tcp --match multiport --sports 80,443,8089,9997 -j ACCEPT
iptables -A INPUT -p icmp -j ACCEPT
iptables -A OUTPUT -f -j DROP
iptables -A OUTPUT -p tcp ! --tcp-flags SYN,ACK SYN -m state --state NEW -j DROP
iptables -A OUTPUT -p udp --match multiport --dports 53,123 -j ACCEPT
iptables -A OUTPUT -p udp --match multiport --sports 53,123 -j ACCEPT
iptables -A OUTPUT -p tcp --match multiport --dports 53 -j ACCEPT
iptables -A OUTPUT -p tcp --match multiport --sports 53 -j ACCEPT
iptables -A INPUT -p tcp ! --tcp-flags SYN,ACK SYN -m state --state NEW -j DROP
iptables -A OUTPUT -p tcp --match multiport --dports 80,443,8089,9997 -j ACCEPT
iptables -A OUTPUT -p tcp --match multiport --sports 80,443,8089,9997 -j ACCEPT
iptables -A OUTPUT -p icmp -j ACCEPT
iptables -A INPUT -p icmp -j ACCEPT
iptables -P FORWARD DROP
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables-save > ~/my.iptables.bck

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
