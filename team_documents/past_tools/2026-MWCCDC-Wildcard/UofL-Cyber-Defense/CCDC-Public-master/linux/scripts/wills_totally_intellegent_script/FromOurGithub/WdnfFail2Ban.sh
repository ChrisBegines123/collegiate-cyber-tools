#!/bin/bash

sudo dnf install fail2ban -y
#confim install
fail2ban-client --version
#setup fail2ban (different log path on apt and dnf for sshd var/log/auth.log v.s. /var/log/secure

sudo tee /etc/fail2ban/jail.local > /dev/null << EOF
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

#enabling fail2ban
sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
#Check Fail2Ban jail status
sudo fail2ban-client status sshd
echo "Fail2Ban Configured"
#REMEMBER TO  temporarily ADD TRUSTED IPs via "ignoreip = ip ip ip"
# if temate gets locked out for needs to access for any reaso
