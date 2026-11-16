#!/bin/bash

# Create the directory if it doesn't exist
mkdir -p /opt/ccdc/apt+apptitude_installers

# Download isntaller packages
wget -P /opt/ccdc/apt+apptitude_installers https://archive.ubuntu.com/ubuntu/pool/universe/a/aptitude/aptitude-common_0.8.13-5ubuntu5_all.deb
wget -P /opt/ccdc/apt+apptitude_installers https://archive.ubuntu.com/ubuntu/pool/universe/a/apt/apt-transport-https_1.6.1_all.deb

# Check if apt is installed
if command -v apt >/dev/null 2>&1; then
    echo "apt is installed."
    # Check if apt is configured correctly by running an update (dry run)
    if sudo apt update >/dev/null 2>&1; then
        echo "apt is configured correctly."
    else
        echo "Error: apt is installed but not configured correctly."
        echo "You may need to fix your apt configuration."
        exit 1
    fi
else
    echo "apt is not installed. Use the Emergency Install Script"
    exit 1
fi
