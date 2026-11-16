#!/bin/bash
# This is a mostly AI generated script with some manual edits to go in and install a file monitoring 
# software and look for changes in the /etc/ directory and put it to the wall. no more changing my configs red team
# Its compatible with APT mostly and that is pretty clear with its asking to use apt.

# it even logs to /var/log/etc_changes.log

# Exit on any error
set -e

echo "Starting installation of /etc monitoring service..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

# Install required package
echo "Installing inotify-tools..."
apt-get update && apt-get install -y inotify-tools

# Create the monitoring script
MONITOR_SCRIPT="/usr/local/bin/etc_monitor.sh"
echo "Creating monitoring script at $MONITOR_SCRIPT..."

cat << 'EOF' > "$MONITOR_SCRIPT"
#!/bin/bash

# Log file location
LOG_FILE="/var/log/etc_changes.log"
MONITOR_DIR="/etc"

# Create log file if it doesn't exist
touch "$LOG_FILE"
chmod 640 "$LOG_FILE"

# Function to log changes with timestamp
log_change() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    wall "WARNING: File change detected in /etc: $1"
}

# Function to handle script termination
cleanup() {
    echo "Stopping file monitoring..."
    exit 0
}

# Set up trap for clean exit
trap cleanup SIGTERM SIGINT

echo "Starting file monitoring on $MONITOR_DIR..."
echo "Logging to $LOG_FILE"

# Monitor directory for changes
inotifywait -m -r "$MONITOR_DIR" -e modify,create,delete,move,attrib --format '%w%f - %e' | while read CHANGE; do
    # Ignore certain files to reduce noise
    if [[ "$CHANGE" != *".swp"* ]] && [[ "$CHANGE" != *".swx"* ]] && [[ "$CHANGE" != *"~"* ]]; then
        log_change "$CHANGE"
        
        # If it's a critical file, send additional alert
        case "$CHANGE" in
            *"passwd"* | *"shadow"* | *"sudoers"* | *"ssh"*)
                wall "CRITICAL: Sensitive file modification detected: $CHANGE"
                logger -p auth.alert "Critical file modification: $CHANGE"
                ;;
        esac
    fi
done
EOF

# Make the script executable
chmod +x "$MONITOR_SCRIPT"

# Create systemd service
echo "Creating systemd service..."
cat << EOF > /etc/systemd/system/etc-monitor.service
[Unit]
Description=Monitor /etc for file changes
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/etc_monitor.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd, enable and start the service
echo "Starting service..."
systemctl daemon-reload
systemctl enable etc-monitor
systemctl start etc-monitor

# Verify service status
echo "Checking service status..."
systemctl status etc-monitor

echo "Installation complete! Monitor is active and will start automatically on boot."
echo "You can view the logs with: tail -f /var/log/etc_changes.log"
echo "To check service status: systemctl status etc-monitor"