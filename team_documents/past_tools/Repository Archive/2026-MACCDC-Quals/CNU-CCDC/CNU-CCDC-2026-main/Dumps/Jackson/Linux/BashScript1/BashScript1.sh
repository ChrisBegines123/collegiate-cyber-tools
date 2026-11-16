#!/bin/bash
# remember to chmod 755 BashScript from directory.

echo "Starting..."

echo "Securing network settings..."

# Enables firewall
echo "Enabling firewall..."
sudo ufw --force enable

# Enables cookie protection
echo "Enabling syn cookie protection..."
sysctl -n net.ipv4.tcp_syncookies

echo "Disabling IPv6..."
echo "net.ipv6.conf.all.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf

echo "Disabling IP forwarding..."
echo 0 | sudo tee /proc/sys/net/ipv4/ip_forward
echo "Preventing IP Spoofing..."
echo "nospoof on" | sudo tee -a /etc/host.conf

echo "Checking for authorized users..."
userslist=$(eval getent passwd "{$(awk '/^UID_MIN/ {print $2}' /etc/login.defs)..$(awk '/^UID_MAX/ {print $2}' /etc/login.defs)}" | cut -d: -f1)
for i in $(more AuthorizedUsers.txt );
do
	checkvar=0
	for b in $userslist;
	do
		if [ "$b" = "$i" ]
		then
			echo "match found"
			checkvar=1
			echo $checkvar
			break
		fi
	done
	if [ $checkvar -eq 0 ]; 						#sees if user exists. if not, add
	then
		sudo adduser "$i"
	fi
	echo "Changing passwords..."
	password='Sigma23*'
	echo "Password used is $password"
	echo "$i:$password" | sudo chpasswd 					#changes passwords to something secure
	echo "done with $i"
done
for a in $userslist;
do
	check2=0
	echo $check2
	for j in $(more AuthorizedUsers.txt);
	do
		if [[ "$j" = "$a" && "$j" != "rand74" ]]
		then
			echo "$a is authorized in $j"
			check2=1
			echo $check2
			break
		fi	
	done
	if [ $check2 -eq 0 ];
	then
		echo "deleting user $a"
		userdel -r "$a"
	fi
done

echo "Updating..."
echo "basic updates..."
sudo apt-get update
sudo apt-get upgrade
sudo apt-get dist-upgrade
echo "enabling automatic updates..."
sudo dpkg-reconfigure --priority=low unattended-upgrades
sudo unattended-upgrade -d
echo "updating firefox..."
sudo apt-get install firefox
echo "remember to add popup blocker and add an adblocker to firefox..."

echo "Fixing programs..."
sudo apt-get remove nmap
sudo apt-get remove zenmap
sudo apt-get remove wireshark
sudo apt-get remove wesnoth
sudo apt-get remove nginx
sudo apt-get remove apache2
sudo apt-get remove netcat
sudo apt-get remove ftp
sudo apt-get remove --purge gnome-mahjongg gnomine gnome-sudoku aisleriot
sudo apt-get autoremove
echo "installing av..."
sudo apt-get install clamav
sudo clamscan -r --remove /

echo "Deleting unauthorized files..."
#find . -type f -name '*.jpg' -delete
#find . -type f -name '*.mp3' -delete
#find . -type f -name '*.mp4' -delete

echo "Opening config files..."
echo "opening login defs to set max age (90), min age (7), warn age (14)"
sudo nano /etc/login.defs
echo "opening ssh defs to 'PermitRootLogin' to No"
sudo nano /etc/ssh/sshd_config
echo "opening common auth. add 'deny=5 unlock_time=1800' to end of pam_tally2.so"
sudo nano /etc/pam.d/common-auth
echo "opening common password. add minlen=8 to pam_unix.so line. add remember=5 to same line. add 'ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-' to pam_cracklib.so."
sudo apt-get install libpam-cracklib
sudo nano /etc/pam.d/common-password
echo "add allow-guest=false to this file. WARNING!!! Previously, this may lead to error on system reboot that VMWare entering low-graphics mode. If that happens, reset the config files from terminal on boot."
sudo nano /usr/share/lightdm/lightdm.conf.d/50-ubuntu.conf

echo "... script has finished."

# Some urls:
# https://www.thefanclub.co.za/how-to/how-secure-ubuntu-1604-lts-server-part-1-basics
# https://github.com/Forty-Bot/linux-checklist
# https://pastebin.com/NS4ng79h
# https://www.stigviewer.com/stig/canonical_ubuntu_16.04_lts/

