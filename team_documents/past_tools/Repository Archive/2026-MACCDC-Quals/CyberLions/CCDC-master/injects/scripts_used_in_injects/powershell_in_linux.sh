#!/bin/bash

# Install prerequisites
sudo apt-get install -y wget apt-transport-https software-properties-common

# Import Microsoft repository GPG key
wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb

# Update package lists again
sudo apt-get update

# Install PowerShell
sudo apt-get install -y powershell
