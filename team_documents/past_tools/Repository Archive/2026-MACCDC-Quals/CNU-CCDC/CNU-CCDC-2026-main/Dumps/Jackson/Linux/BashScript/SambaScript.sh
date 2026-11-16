#!/bin/bash
# finish forensics questions before running this. REMEMBER WHAT HAPPENED IN ROUND 2 of CP XII.

echo "Starting ..."

echo "Updating Apache..."
sudo apt-get install apache2

echo "Backing up files..."
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak

echo 'Rememeber to set the following:
    /etc/samba/smb.conf
'