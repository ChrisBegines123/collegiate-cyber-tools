#!/bin/bash

# Define the banner message
BANNER_MESSAGE="**************************************************************
*                                                            *
*             WARNING: AUTHENTICATION REQUIRED               *
*                                                            *
*        Unauthorized access is prohibited and may be        *
*                    punishable by law.                      *
*          All activities on this system are logged.         *
*                                                            *
**************************************************************"
# Create or overwrite /etc/ssh/banner
echo "$BANNER_MESSAGE" | sudo tee /etc/ssh/banner > /dev/null
# Configure ssh_config to use the banner
if grep -q "^Banner" /etc/ssh/ssh_config; then
    sudo sed -i 's|^Banner.*|Banner /etc/ssh/banner|' /etc/ssh/ssh_config
else
    echo "Banner /etc/ssh/banner" | sudo tee -a /etc/ssh/ssh_config > /dev/null
fi
# Update /etc/motd
echo "$BANNER_MESSAGE" | sudo tee /etc/motd > /dev/null
# Update /etc/issue and /etc/issue.net (typically used for pre-login messages)
sudo tee /etc/issue > /dev/null <<EOF
$BANNER_MESSAGE
EOF
sudo tee /etc/issue.net > /dev/null <<EOF
$BANNER_MESSAGE
EOF
echo "Login banner configuration completed."
