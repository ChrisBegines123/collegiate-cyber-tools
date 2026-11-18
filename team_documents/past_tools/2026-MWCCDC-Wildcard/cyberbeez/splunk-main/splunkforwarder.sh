#!/bin/bash

#When running, in order to work, run (bash splunkforwarder.sh 172.20.241.20) (The corresponding splunk server address must be added to append for $1 on line 24)

##Grab File
sudo wget "https://download.splunk.com/products/universalforwarder/releases/9.4.1/linux/splunkforwarder-9.4.1-e3bdab203ac8-linux-amd64.tgz"
##Move File
sudo mv ./splunkforwarder-9.4.1-e3bdab203ac8-linux-amd64.tgz /opt/

cd /opt/
##Unpack - Extract
sudo tar -xvzf splunkforwarder-9.4.1-e3bdab203ac8-linux-amd64.tgz
##Accept Licensing
sudo /opt/splunkforwarder/bin/splunk start --accept-license

cd /opt/splunkforwarder/bin/
##Start on Boot
sudo ./splunk enable boot-start -user sysadmin
##Changes File Ownership - Prevents ./splunk start corruption issues
sudo chown -R sysadmin:sysadmin /opt/splunkforwarder
##Ensure to type Splunk Server IPv4 Address when running for the pos arg.
sudo ./splunk add forward-server $1:9997
##Set File Monitor
sudo ./splunk add monitor /var/log/
##Restart
sudo ./splunk restart
