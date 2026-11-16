#!/usr/bin/env bash
# Author: Collin Dewey
# Description:
# Changes postfix from using LDAP to dovecot for auth. Do this. Don't say I didn't warn you.
# Usage:
# ./<Script_Name>

. $(dirname "$0")/helper.sh; if [ -z ${PUBLIC_KEY+x} ]; then exit 1; fi
root_check

# Backup Postfix and Dovecot configurations
postconf -n > /etc/postfix_config-orig
doveconf -n > /etc/dovecot_config-orig
cp -R /etc/dovecot /etc/dovecot-orig
cp -R /etc/postfix /etc/postfix-orig
cp /etc/aliases /etc/aliases-orig

encrypt /etc/postfix_config-orig
encrypt /etc/dovecot-config-orig

# REM out LDAP configuration
sed -i "s/alias_maps =/#alias_maps =/g" /etc/postfix/main.cf
sed -i "s/smtpd_sender_login_maps = proxy/#smtpd_sender_login_maps = proxy/g" /etc/postfix/main.cf
sed -i "s/virtual_mailbox_maps = proxy/#virtual_mailbox_maps = proxy/g" /etc/postfix/main.cf

# Use dovecot for authentication
echo "
alias_maps = hash:/etc/aliases
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination
" >> /etc/postfix/main.cf

# Add aliases for mail users
awk -F: '$3 > 5000 {print $1 ": " $1}' /etc/passwd | tee -a /etc/aliases

# Set group override
mkdir -p /etc/systemd/system/postfix.service.d
mkdir -p /etc/systemd/system/dovecot.service.d
cat "[Service]
Group=mail_in" > /etc/systemd/system/postfix.service.d/override.conf
cat "[Service]
Group=mail_in" > /etc/systemd/system/dovecot.service.d/override.conf

# Restart services
systemctl daemon-reload
systemctl restart postfix
systemctl restart dovecot