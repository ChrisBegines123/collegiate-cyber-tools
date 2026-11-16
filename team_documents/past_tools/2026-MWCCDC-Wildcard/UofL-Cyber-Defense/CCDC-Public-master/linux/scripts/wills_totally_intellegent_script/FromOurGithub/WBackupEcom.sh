#!/bin/bash

# source directories to check
dirs=(
  "/var/www"
  "opencart"
  "opencartmaster"
  "opencart-master"
  "/var/mail"
  "/etc/nginx"
  "/etc/apache2"
  "/var/name"
  "/etc/iptables"
  "/var/log"
)

# backup destination
sudo mkdir /opt/ccdc/auto-backups
backup_dir="/opt/ccdc/auto-backups"

sudo rsync -avz /etc/resolve.conf $backup_dir
sudo rsync -avz /var/www $backup_dir
sudo rsync -avz /var/mail $backup_dir
sudo rsync -avz /etc/nginx $backup_dir
sudo rsync -avz /etc/apache2 $backup_dir
sudo rsync -avz /etc/iptables $backup_dir
sudo rsync -avz /var/log $backup_dir
sudo rsync -avz /home/sysadmin $backup_dir

# Loop through patterns and find matching directories
#for dir in "${dirs[@]}"; do
  # Use find to locate directories matching the pattern
 # matches=$(find / -type d -name "${dir}" 2>/dev/null)

  #if [ -n "$matches" ]; then
    # Copy the directories to the backup directory
   # for match in $matches; do
    #  cp -r "$match" "$backup_dir"
    #done
  #fi
#done
