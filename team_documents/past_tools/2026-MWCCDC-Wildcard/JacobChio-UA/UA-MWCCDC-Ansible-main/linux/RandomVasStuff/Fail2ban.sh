#!/bin/bash

# Fail2ban setup script for Postfix

set -e

echo "idk amongus but fail2ban"
sudo apt-get update
sudo apt-get install -y fail2ban

echo "Creating Postfix jail configuration..."
sudo tee /etc/fail2ban/jail.d/postfix.conf > /dev/null <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[postfix-sasl]
enabled = true
port = smtp,ssmtp,submission,imap2,imap3,imaps,pop3,pop3s
filter = postfix[mode=auth]
logpath = /var/log/mail.log
maxretry = 5

[postfix-bounce]
enabled = true
port = smtp,ssmtp
filter = postfix-bounce
logpath = /var/log/mail.log
maxretry = 10

[postfix-aggressive]
enabled = true
port = smtp,ssmtp
filter = postfix-aggressive
logpath = /var/log/mail.log
maxretry = 3
EOF

echo "Enabling and starting fail2ban..."
sudo systemctl enable fail2ban
sudo systemctl restart fail2ban

echo "Checking fail2ban status..."
sudo fail2ban-client status

echo "Fail2ban setup for Postfix complete!"