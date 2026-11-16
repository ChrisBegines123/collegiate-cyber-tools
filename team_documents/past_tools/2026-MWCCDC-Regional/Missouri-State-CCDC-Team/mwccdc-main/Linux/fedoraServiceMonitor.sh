# ==============================================================================
# Script Name : fedoraServiceMonitor.sh
# Description : Monitors the fedora services for any chnages and will wall if detected.
# Author      : Tyler Olson
# Organization: Missouri State University
# Version     : 1.1 - Addition of these notes
# ==============================================================================
#!/bin/bash
set -e

# Ensure only root can run this
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root or with sudo privileges"
    exit 1
fi

echo "[+] Creating monitor script at /usr/local/bin/serv-monitor.sh..."
cat > /usr/local/bin/serv-monitor.sh << 'EOF'
#!/bin/bash
SERVICES=("dovecot" "postfix")

check_services() {
  for svc in "${SERVICES[@]}"; do
    if ! systemctl is-active --quiet "$svc"; then
      systemctl restart "$svc"
      wall "ALERT: $svc was stopped and has been restarted by serv-monitor."
    fi
  done
}

while true; do
  check_services
  sleep 10
done
EOF

chmod +x /usr/local/bin/serv-monitor.sh
chown root:root /usr/local/bin/serv-monitor.sh

echo "Creating systemd service unit..."
cat > /etc/systemd/system/serv-monitor.service << 'EOF'
[Unit]
Description=Service Monitor for dovecot and postfix
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/serv-monitor.sh
Restart=always
RestartSec=5
User=root
Nice=-10
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=yes
PrivateTmp=true
CapabilityBoundingSet=CAP_KILL CAP_SYS_ADMIN CAP_SYS_PTRACE CAP_SYS_RESOURCE
RestrictRealtime=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
SystemCallFilter=@system-service

[Install]
WantedBy=multi-user.target
EOF

echo "Reloading systemd and enabling the service..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now serv-monitor.service

echo "[+] Setting immutable flag on script to prevent tampering..."
chattr +i /usr/local/bin/serv-monitor.sh || echo "Could not set immutable flag. You may need to enable ext4 attributes."

echo "serv-monitor has been installed and is now running."
