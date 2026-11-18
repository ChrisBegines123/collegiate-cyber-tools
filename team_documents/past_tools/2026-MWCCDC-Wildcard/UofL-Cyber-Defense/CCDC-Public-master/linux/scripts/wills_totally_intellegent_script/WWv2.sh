#!/bin/bash
#-----
#Root Check
#-----
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root!" >&2
    exit 1
fi
#-----
#-----
# In Case Of Emergency
#-----
# bash trap command can execute a subroutine when X condition occurs
trap bashtrap INT
# bash trap function is executed when CTRL-C is pressed:
bashtrap()
{
    \n
    echo "CTRL+C Detected! Exiting Script Early!"

    exit 1
}
#-----
#----- 
# IMPORTANT VARIABLES TO SET
#-----
su="U"
#-----
#-----
#Securing Admin Account and OSetting Up Helper
#-----
echo "Enter new password for $su"
    passwd $su </dev/tty
chmod a+x ./FromOurGithub/helper.sh
/bin/bash ./FromOurGithub/helper.sh
#-----
#-----
#Auditing packages
#-----
#make callable
chmod a+x ./FromOurGithub/audit_packages.sh
#Call
/bin/bash ./FromOurGithub/audit_packages.sh
#-----
#-----
# Setting Package Manager
#-----
# Set default value for pkmt
pkmtc=0

read -p "Do you want to use apt (1) or dnf (2)?" -n 1 c

# Check if user has provided a value for pkmt
if [ -n "$c" ]; then
	if [ "$c" == "1" ] || [ "$c" == "2" ]; then
		pkmtc=$c
	else
		echo "Invalid value for pkmt. Please enter 1 (for apt) or 2 (for dnf)."
		exit 1
	fi
fi

# Set the package manager (pkmt) based on user choice (c) 
case $pkmtc in
	1) pkmt=apt ;;
	2) pkmt=dnf ;;
	*) echo "Invalid value for pkmt. Please enter 1 (for apt) or 2 (for dnf)."
		exit 1 ;;
esac

# Declaration of package manager
echo "The package manager that has been chosen is: $pkmt"
#-----
#-----
# Upgrading System
#-----
sudo $pkmt update -y && sudo $pkmt upgrade -y
#-----
#-----
#SSH Killer from Collin (Author)
#-----
if [ -f /usr/lib/systemd/system/sshd.service ] || [ -f /lib/systemd/system/sshd.service ]; then
    NAME=sshd
else
    NAME=ssh
fi

if systemctl is-active --quiet $NAME 2>/dev/null; then
    systemctl stop $NAME
fi

if ! systemctl is-enabled --quiet $NAME 2>/dev/null; then
    systemctl mask $NAME
fi

if pgrep sshd >/dev/null; then
    kill -9 $(pgrep sshd)
fi
#-----
#-----
#Clear old SSH Keys (modified Collin's work) 
#-----
 for user in /home/*; do rm -f "$user/.ssh/authorized_keys"; done
rm -f /root/.ssh/authorized_keys
# In case deleting the root key folder errors, use "chattr -i" and try again
chattr -i /root/.ssh/authorized_keys
#-----
#-----
#Disable Cron
#-----
sudo /etc/init.d/cron stop
#Disabling user access to cron (thanks Collin!)
move /usr/sbin/cron
cut -d: -f1 /etc/passwd | tail -n+2 >> /etc/cron.deny
#-----
#-----
# ClamAV Setup
#-----
case $pkmt in
  apt) $pkmt install clamav clamscan clamav-daemon;;
  dnf) $pkmt install ;;
esac
echo "Enabling Clam AV Services..."
sudo systemctl enable --now clamav-daemon && sudo systemctl status clamav-daemon && sudo freshclam && sudo enable --now clamav--freshclam && sudo systemctl status clamav--freshclam
#Making directory for ClamAV to put infected stuff
sudo mkdir -p /var/log/clamav/infected
echo "Scheduling ClamAV runs & Services..."
#Creating custom clamscan service
sudo tee /etc/systemd/system/clamscan.service <<EOF
[Unit]
Description=Custom ClamAV Scan

[Service]
Type=oneshot
Nice=10
ExecStart=/usr/bin/clamscan -r --exclude-dir=^/sys --exclude-dir=^/proc --exclude-dir=^/dev --move=/var/log/clamav/infected /home /var/www/html
EOF
#Creating clamscan.service timer
sudo tee /etc/systemd/system/clamscan.timer <<EOF
[Unit]
Description=Scheduling Custom ClamAV Scan

[Timer]
OnBoot=10min
OnUnitActiveSec=20min
Persistent=true

[Install]
WantedBy=timers.target
EOF
#Enabling the timer
sudo systemctl enable --now clamscan.timer
sudo systemctl daemon-reload
#Confirm working timer
sudo systemctl list-timers | grep -i clamscan
sudo systemctl status clamscan.timer
#-----
#-----
# Fail2Ban Setup
#-----
#make sure fail2ban is installed
sudo $pkmt install fail2ban -y
#confim install
fail2ban-client --version
#setup fail2ban (different log path on apt and dnf for sshd var/log/auth.log v.s. /var/log/secure
case $pkmt in
  apt)sudo tee /etc/fail2ban/jail.local > /dev/null << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sendername = Fail2Ban
action = %(action_mwl)s

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log

[apache-auth]
enabled = true
port = http,https
logpath = /var/log/apache*/*error.log
EOF
;;
  dnf)sudo tee /etc/fail2ban/jail.local > /dev/null << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sendername = Fail2Ban
action = %(action_mwl)s

[sshd]
enabled = ${ssh_has_password_auth}
port = ssh
logpath = /var/log/secure

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log

[apache-auth]
enabled = true
port = http,https
logpath = /var/log/apache*/*error.log
EOF
esac
#enabling fail2ban
sudo systemctl daemon-reload
sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
#Check Fail2Ban jail status
sudo fail2ban-client status sshd
echo "Fail2Ban Configured"
#REMEMBER TO  temporarily ADD TRUSTED IPs via "ignoreip = ip ip ip"
# if temate gets locked out for needs to access for any reason
#-----
#-----
#Wazuh Agent Install
#-----
case $pkmt in
  apt)#Install
$pkmt install gnupg apt-transport-https && curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && chmod 644 /usr/share/keyrings/wazuh.gpg && echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | tee -a /etc/apt/sources.list.d/wazuh.list && $pkmt update
#Deploy
WAZUH_MANAGER="10.0.0.2" apt-get install wazuh-agent;;
  dnf)#Install
rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH && cat > /etc/yum.repos.d/wazuh.repo << EOF
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-\$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
priority=1
EOF
#Deploy (IP points to Splunk machine)
WAZUH_MANAGER="172.20.242.20" dnf install wazuh-agent
esac
#Enable
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
#-----
# Firewall Setup
#-----
#make callable
chmod a+x ./FromOurGithub/setup_firewall.sh
#Call
/bin/bash ./FromOurGithub/setup_firewall.sh
echo "firewall.sh finished?"
#-----
#-----
#Login Banner
#-----
# Define the banner message
BANNER_MESSAGE="**************************************************************
*                                                            *
*             WARNING: AUTHENTICATION REQUIRED               *
*                                                            *
*        Unauthorized access is prohibited and may be        *
*                    punishable by law.                      *
*          All activities on this system are logged.         *
*                                                            *
**************************************************************"
# Create or overwrite /etc/ssh/banner
echo "$BANNER_MESSAGE" | sudo tee /etc/ssh/banner > /dev/null
# Configure ssh_config to use the banner
if grep -q "^Banner" /etc/ssh/ssh_config; then
    sudo sed -i 's|^Banner.*|Banner /etc/ssh/banner|' /etc/ssh/ssh_config
else
    echo "Banner /etc/ssh/banner" | sudo tee -a /etc/ssh/ssh_config > /dev/null
fi
# Update /etc/motd
echo "$BANNER_MESSAGE" | sudo tee /etc/motd > /dev/null
# Update /etc/issue and /etc/issue.net (typically used for pre-login messages)
sudo tee /etc/issue > /dev/null <<EOF
$BANNER_MESSAGE
EOF
sudo tee /etc/issue.net > /dev/null <<EOF
$BANNER_MESSAGE
EOF
echo "Login banner configuration completed."
#-----
#-----
#Installing rkhunter for later use
#-----
sudo $pkmt install rkhunter -y
echo "rkhunter installed for later use"
#-----
#-----
#Honeypot
#-----
chmod a+x ./FromOurGithub/setup_nix.sh
chmod a+x ./FromOurGithub/setup_honeypot.sh
/bin/bash ./FromOurGithub/setup_nix.sh
/bin/bash ./FromOurGithub/setup_honeypot.sh
#-----
#-----
#Securing Root Account and Other Such Security Measures
#-----
echo "Enter new password for $su"
    passwd $su </dev/tty
chmod a+x ./FromOurGithub/setup_users.sh
/bin/bash ./FromOurGithub/setup_users.sh
chmod a+x ./FromOurGithub/setup_syslog.sh
/bin/bash ./FromOurGithub/setup_syslog.sh
#-----



