#!/usr/bin/env bash

set -euo pipefail

src_dir=$(dirname "$(realpath "$0")")
source "${src_dir}/commonFuctions.sh"

echo "Checking if i'm running as root."
logger "Checking if i'm running as root."

USER=$(whoami)
if [[ "$USER" != "root" ]]; then
  echo "Run me as root. Exiting!"
  logger "Run me as root. Exiting!" 
  exit 1
fi

echo "changing passwords"
logger "changing passwords"

echo "changing root password"
logger "changing root password"
passwd

echo "changing sysadmin password"
logger "changing sysadmin password"
passwd sysadmin

echo "Showing what groups sysadmin as apart of"
groups sysadmin
read -p "Enter the default admin group " default_admin_group
echo "Users in admin group"
getent group $default_admin_group

echo "adding ssn to admin group"
logger "adding ssn to admin group"

useradd ssn -G $default_admin_group

echo "changing ssn password"
logger "changing snn password"
passwd ssn

echo "Locking sysadmin account"
logger "Locking sysadmin account"
usermod -L sysadmin

echo "Checking systemctl"
systemctl list-units --type=service --state=running
sysemctl_output=$(systemctl list-units --type=service --state=running)
logger $sysemctl_output
echo "Checking cron"
crontab -e
crontab_e_loger=$(crontab -e)
logger $crontab_e_loger

sudo vi /etc/crontab
system_crontab=$(cat /etc/crontab)
logger crontab
echo finished
