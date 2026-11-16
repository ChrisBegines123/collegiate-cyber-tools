#!/bin/bash

#---------------------
#apt unique
#Install
rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH && cat > /etc/yum.repos.d/wazuh.repo << EOF
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-\$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
priority=1
EOF
#Deploy (IP points to Splunk machine)
WAZUH_MANAGER="172.20.242.20" dnf install wazuh-agent;;
#-------------
#pagakemenater nonimportant
#Enable
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
