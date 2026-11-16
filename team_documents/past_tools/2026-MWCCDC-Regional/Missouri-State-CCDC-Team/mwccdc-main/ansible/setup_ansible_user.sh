#!/bin/bash 
# ==============================================================================
# Script Name : ansibleuser.sh
# Description : If we have the time to use ansible for our network. Through ssh this will set up and ansible user with a supplied public key file for ansible.
# Author      : Tyler Olson
# Organization: Missouri State University
# Version     : 1.0
# ==============================================================================
# Usage       : ./setup_ansible_user.sh <server> <public_key_file>
# Notes       :
#   - This will go in and create a user, asking for a password for the user. 
# ==============================================================================

set -e

# Usage check
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <server> <ssh_public_key_file>"
    exit 1
fi

SERVER=$1
SSH_KEY_FILE=$2
USERNAME="ansible"

# Ensure the SSH key file exists
if [ ! -f "$SSH_KEY_FILE" ]; then
    echo "Error: SSH public key file not found: $SSH_KEY_FILE"
    exit 1
fi

# Prompt for the password securely
echo -n "Enter password for user ${USERNAME}: "
read -s PASSWORD
echo "\n"

# Run commands on the remote server to create the user, set the password,
# and create the .ssh directory.
ssh "$SERVER" <<EOF
    sudo useradd -m -s /bin/bash $USERNAME
    echo "$USERNAME:$PASSWORD" | sudo chpasswd
    sudo mkdir -p /home/$USERNAME/.ssh
    sudo chmod 700 /home/$USERNAME/.ssh
EOF

# Transfer the SSH public key to the remote server
scp "$SSH_KEY_FILE" "$SERVER:/tmp/ansible_key.pub"

# Append the public key to authorized_keys and set proper permissions
ssh "$SERVER" <<EOF
    sudo cat /tmp/ansible_key.pub | sudo tee -a /home/$USERNAME/.ssh/authorized_keys
    sudo chmod 600 /home/$USERNAME/.ssh/authorized_keys
    sudo chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
    sudo rm /tmp/ansible_key.pub
EOF

echo "User '${USERNAME}' created and SSH key added successfully on $SERVER."
