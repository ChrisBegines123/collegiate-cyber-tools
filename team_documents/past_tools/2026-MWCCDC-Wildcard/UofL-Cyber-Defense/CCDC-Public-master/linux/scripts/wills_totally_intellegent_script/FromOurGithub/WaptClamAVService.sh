#!/bin/bash

#-----
# Only part different for apt and dnf?
sudo apt install clamav clamscan clamav-daemon
#------

#Below should be same for apt and dnf
echo "Enabling Clam AV Services..."
sudo systemctl enable --now clamav-daemon && sudo systemctl status clamav-daemon && sudo freshclam && sudo enable --now clamav--freshclam && sudo systemctl status clamav--freshclam
#Making directory for ClamAV to put infected stuff
sudo mkdir -p /var/log/clamav/infected
echo "Scheduling ClamAV runs & Services..."
#Creating custom clamscan service
sudo tee /etc/systemd/system/clamscan.service <<EOF
[Unit]
Description=Custom ClamAV Scan

[Service]
Type=oneshot
Nice=10
ExecStart=/usr/bin/clamscan -r --exclude-dir=^/sys --exclude-dir=^/proc --exclude-dir=^/dev --move=/var/log/clamav/infected /home /var/www/html
EOF
#Creating clamscan.service timer
sudo tee /etc/systemd/system/clamscan.timer <<EOF
[Unit]
Description=Scheduling Custom ClamAV Scan

[Timer]
OnBoot=10min
OnUnitActiveSec=20min
Persistent=true

[Install]
WantedBy=timers.target
EOF
#Enabling the timer
sudo systemctl enable --now clamscan.timer
sudo systemctl daemon-reload
#Confirm working timer
sudo systemctl list-timers | grep -i clamscan
sudo systemctl status clamscan.timer
