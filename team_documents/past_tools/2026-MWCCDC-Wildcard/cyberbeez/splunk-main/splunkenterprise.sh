#!/bin/bash

##Grab File
sudo wget "https://download.splunk.com/products/splunk/releases/9.4.1/linux/splunk-9.4.1-e3bdab203ac8-linux-amd64.tgz"
##Move File
sudo mv ./splunk-9.4.1-e3bdab203ac8-linux-amd64.tgz /opt/

cd /opt/
##Unpack - Extract
sudo tar -xvzf splunk-9.4.1-e3bdab203ac8-linux-amd64.tgz
##Accept Licensing
sudo /opt/splunk/bin/splunk start --accept-license

cd /opt/splunk/bin/
##Start on Boot
sudo ./splunk enable boot-start -user sysadmin
##Changes File Ownership - Prevents ./splunk start corruption issues
sudo chown -R sysadmin:sysadmin /opt/splunk
##Restart
sudo ./splunk restart
