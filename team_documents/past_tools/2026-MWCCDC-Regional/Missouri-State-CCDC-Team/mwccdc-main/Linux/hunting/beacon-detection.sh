# If another platform isn't used. this script is used to watch network connections for a bit a
# Finding connections going every so often 

# Duration to monitor (in seconds)
DURATION=300
END_TIME=$((SECONDS + DURATION))

# Check if toor
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root or with sudo privileges"
    exit 1
fi

echo "Monitoring network connections for $DURATION seconds..."
while [ $SECONDS -lt $END_TIME ]; do
    echo -e "\n--- Network Connections at $(date) ---"
    netstat -tunap
    sleep 30
done
echo "Monitoring complete."

