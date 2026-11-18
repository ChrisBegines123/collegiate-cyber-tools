#!/bin/bash

#Removes useless programs
yum remove xinetd telnet-server rsh-server \telnet rsh ypbind ypserv tfsp-server bind \vsfptd dovecot squid net-snmpd talk-server talk -y

#Installs repository
yum install epel-release -y

#Installs clamav
yum install clamav clamav-update -y
freshclam

#Installs iptables
yum install iptables-services -y

#Install git
yum install git -y

#Install nmap
yum install nmap -y

#Install lynis
yum install lynis -y

#Disables accounts with no passowrds from loggin
sed -i 's/nullok//g' /etc/pam.d/system-auth

#Disallow apache from showing directories
sed -i "s/Options Indexes FollowSymLinks/Options FollowSymlinks/" /etc/httpd/conf/httpd.conf
