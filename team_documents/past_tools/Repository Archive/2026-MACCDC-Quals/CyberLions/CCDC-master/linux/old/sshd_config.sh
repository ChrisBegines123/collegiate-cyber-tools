#!/bin/bash

# root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root."
  exit 1
fi

# variables
sshd_config="/etc/ssh/sshd_config"
backup_file="${sshd_config}.bak"

# create backup?
if [ -f "${sshd_config}" ];then
	echo "Creating a backup of $sshd_config at $backup_file"
	cp "$sshd_config" "$backup_file"
else
	echo "Error: $sshd_config does not exist."
	exit 1
fi

# function sets or updates config params
set_config() {
    local param="$1"
    local value="$2"

    # remove existing params
    sed -i "/^${param}/d" "$sshd_config"

    # add new param-value pairs at end of file
    echo "${param} ${value}" >> "$sshd_config"
}

set_config "PermitRootLogin" "no"
set_config "ChallengeResponseAuthentication" "no"
set_config "PasswordAuthentication" "no"
set_config "PermitEmptyPasswords" "no"
set_config "X11Forwarding" "no"

grep Protocol /etc/ssh/sshd_config | grep 1
if [ $?==0 ]
then
  sed -i 's/Protocol 2,1/Protocol 2/g' /etc/ssh/sshd_config
  sed -i 's/Protocol 1,2/Protocol 2/g' /etc/ssh/sshd_config
fi

echo "Restarting SSHD service..."
if systemctl restart sshd; then
    echo "SSHD reloaded successfully."
else
    echo "Error: Failed to reload SSHD."
fi
