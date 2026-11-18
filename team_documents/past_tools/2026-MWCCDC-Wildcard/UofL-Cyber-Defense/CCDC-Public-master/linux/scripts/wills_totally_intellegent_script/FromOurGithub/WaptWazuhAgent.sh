#!/bin/bash

#---------------------
#apt unique
#Install
$pkmt install gnupg apt-transport-https && curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && chmod 644 /usr/share/keyrings/wazuh.gpg && echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | tee -a /etc/apt/sources.list.d/wazuh.list && $pkmt update
#Deploy
WAZUH_MANAGER="10.0.0.2" apt-get install wazuh-agent;;
#-------------
#pagakemenater nonimportant
#Enable
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
