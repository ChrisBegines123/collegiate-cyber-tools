#!/bin/bash

#Run program after running inprograms.sh file

#Stop firewalld
systemctl stop firewalld
systemctl disable firewalld
systemctl mask --now firewalld

#Stop libvirtd
systemctl stop libvirtd
systemctl disable libvirtd

#IPtables rules
iptables -F
iptables -P FORWARD DROP
iptables -A INPUT -f -j DROP
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --sport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --sport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport 3306 -j ACCEPT
iptables -A INPUT -p tcp --sport 3306 -j ACCEPT

iptables -A INPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A INPUT -p udp --dport 123 -j ACCEPT
iptables -A INPUT -p udp --sport 123 -j ACCEPT
iptables -A INPUT -p icmp -j ACCEPT
iptables -A INPUT -j DROP

iptables -A OUTPUT -f -j DROP
iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT
iptables -A OUTPUT -p tcp --sport 80 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT
iptables -A OUTPUT -p tcp --sport 443 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 3306 -j ACCEPT
iptables -A OUTPUT -p tcp --sport 3306 -j ACCEPT

iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p udp --sport 53 -j ACCEPT
iptables -A OUTPUT -p udp --dport 123 -j ACCEPT
iptables -A OUTPUT -p udp --sport 123 -j ACCEPT
iptables -A OUTPUT -p icmp -j ACCEPT
iptables -A OUTPUT -j DROP

#IP6tables rules
ip6tables -F
ip6tables -P FORWARD DROP
ip6tables -P INPUT DROP
ip6tables -P OUTPUT DROP

#Backup for iptables
iptables-save > tablesbackup.txt
ip6tables-save > tables6backup.txt

#To restore type:
#iptables-restore < tablesbackup.txt

#Disable IPv6
if ! grep -q "net.ipv6.conf.all.disable_ipv6 = 1" /etc/sysctl.conf; then 
	echo "#Disable IPv6
	net.ipv6.conf.all.disable_ipv6 = 1
	net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
	systemctl restart network
fi

#Saves changes
service iptables save
service ip6tables save

systemctl enable iptables
systemctl restart iptables

systemctl enable ip6tables
systemctl restart ip6tables
