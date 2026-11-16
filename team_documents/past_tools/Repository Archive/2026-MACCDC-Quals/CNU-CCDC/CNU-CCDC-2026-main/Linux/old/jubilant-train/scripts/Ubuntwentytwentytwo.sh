#!/bin/bash

#SETTINGS

#list of software to be installed or updated
allowedSoftware=("nano")

#list of software to be removed
prohibitedSoftware=("nmap" "hydra" "keylogger" "metasploit" "hashcat" "samba" "zenmap" "apache2" "nginx" "lighttpd" "wireshark" "tcpdump" "netcat-traditional" "nikto" "ophcrack")

#list of prohibited file types to be removed/purged
prohibitedFileTypes=("mp3", "mp4", "jpeg", "png", "dds", "jpg", "tar.gz", "tgz", "zip", "deb")

#START

echo "Team Sigma - influenced by the influencer"
cd /

#remove prohibited file types
read -p "remove prohibited file types? (only if you don't need media files; run AFTER forensics questions) [y/n] " runFileTypeRemoval

if [$runFileTypeRemoval == "y"]
then
    echo "removing prohibited file types"
    for fileType in $prohibitedFileTypes; do
        echo "removing .$fileType files"
        find . -name "*.$fileType" -type f -delete &> /dev/null
    done
else
    echo "skipping prohibited file removal process"
fi

#fetch the latest package list
echo "fetching latest packages and installing updates"
apt-get update
apt-get upgrade
apt-get dist-upgrade

#update firefox
echo "updating firefox"
apt update firefox -y &> /dev/null

#enable uncomplicated firewall
echo "installing and enabling UFW"
apt-get install ufw
ufw enable

#lock root user
echo "locking root user"
passwd -l root

#install or update allowed software
for software in $allowedSoftware; do
    echo "installing/updating $software"
    apt install $software -y &> /dev/null
done

#purge prohibited software
for software in $prohitbitedSoftware; do
    if ! command -v $software &> /dev/null
    then
        echo "$software not found"
    else
        apt-get purge $software -y &> /dev/null
        echo "$software purged"
    fi
done

#SSH manual

read -p "view SSH manual? [y/n] " sshDecision

if [$sshDecision == "y"]
then
    echo "starting SSH manual - press any key to continue"
    read -p ""
    echo "Step 1: Navigate  to /etc/ssh using cd"
    read -p ""
    echo "Step 2: Edit the sshd_config file using nano. Ex: nano sshd_config"
    read -p ""
    echo "Step 3a: Find the following line: 'Port 22' or '#Port 22' and change it to 'Port 2025'"
    read -p ""
    echo "Step 3b: Add the following line to the bottom of the file: 'ClientAliveInterval 300'"
    read -p ""
    echo "Step 3c: Add the following line to the bottom of the file: 'ClientAliveCountMax 0'"
    read -p ""
    echo "Step 3d: Find the following line and edit or add it to the bottom of the file if it does not exist: 'PermitEmptyPasswords no'"
    read -p ""
    echo "Step 3e: Go to the bottom of the file and for each administrative user add this line: 'AllowUsers AdminUser'"
    read -p ""
    echo "Step 3f: Find and edit the following line: 'PermitRootLogin no'"
    read -p ""
    echo "Step 3g: Find and edit the following line or add it the bottom of the file if it does not exist: 'Protocol 2'"
    ufw allow 2025
    service ssh restart
fi