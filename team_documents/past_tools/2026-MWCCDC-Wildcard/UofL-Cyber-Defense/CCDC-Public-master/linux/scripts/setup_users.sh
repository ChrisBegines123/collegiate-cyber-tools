#!/usr/bin/env bash
# Author: Collin Dewey
# Description:
# Sets up groups and users
# Usage: 
# ./<Script_Name>

. $(dirname "$0")/helper.sh; if [ -z ${PUBLIC_KEY+x} ]; then exit 1; fi
root_check

PATH=/usr/sbin/:/sbin/:$PATH

mkdir -p /opt/ccdc

if [[ $(hostname -s) == "fedora" ]]; then
    userdel system
    chattr -i /usr/sbin/nologin
    cp /bin/false /usr/sbin/nologin
    for user in $(grep -vE '/bin/false|/usr/sbin/nologin' /etc/passwd | cut -d: -f1); do
        echo "Changing Account Shell: $user"
        usermod --shell /usr/sbin/nologin $user
    done
else
    awk -F: '($2 != "" && $2 !~ /^[!*]/) {system("echo Locking Account: "$1"; usermod --lock "$1)}' /etc/shadow # Isn't AI cool?
    for user in $(grep -vE '/bin/false|/usr/sbin/nologin' /etc/passwd | cut -d: -f1); do
        echo "Changing Account Shell: $user"
        usermod --shell /usr/sbin/nologin $user
    done
fi
create_user ccdc

while true; do
    echo "Enter new password for root"
    passwd root </dev/tty
    if [[ $? -eq 0 ]]; then
        break
    fi
done
usermod -s /bin/bash -U root
while true; do
    echo "Enter new password for ccdc"
    passwd ccdc </dev/tty
    if [[ $? -eq 0 ]]; then
        break
    fi
done
usermod -d /opt/ccdc -s /bin/bash -U ccdc
mkdir -p /etc/sudoers.d
echo "ccdc ALL=(ALL) ALL" > /etc/sudoers.d/ccdc
chown -R ccdc /opt/ccdc

# GDM
if [ -d /var/lib/AccountsService/users ]; then
    echo -e "[User]\nSystemAccount=false" > /var/lib/AccountsService/users/ccdc
fi

create_group internet_out
sed -i 's/internet_out:!::/internet_out:$1$EX3DJOZZ$mNk.jlKMwAyl1GGO2lsH90::/g' /etc/gshadow # This is a lowercase y
create_group mail_in
create_group ntp_in
create_group dns_in
create_group http_in
create_group honeypot_in
create_group ssh_in
create_group sshusers