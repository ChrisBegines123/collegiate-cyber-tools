#!/bin/bash

# Variables
LOG_FILE="/var/log/syslog"        # Change this to your firewall log file if different
THRESHOLD=10                       # Number of connection attempts to trigger detection
TIME_FRAME=60                      # Time frame in seconds for counting attempts
BLOCKED_IP_FILE="./blocked_ips.log"

# Function to block IP using iptables
block_ip() {
  local ip=$1
  echo "Blocking IP: $ip"
  # Block the IP using iptables; change to your firewall rule if needed
  iptables -A INPUT -s "$ip" -j DROP
  echo "$(date): Blocked IP $ip due to potential port scanning" >> "$BLOCKED_IP_FILE"
}

# Function to detect port scan attempts
detect_port_scan() {
  echo "Checking for potential port scans..."
  
  # Use awk to filter log entries for the last TIME_FRAME seconds
  current_time=$(date +%s)
  awk -v threshold="$THRESHOLD" -v time_frame="$TIME_FRAME" -v current_time="$current_time" '
  {
    # Extract timestamp and convert to epoch for comparison
    timestamp = substr($1, 1, 15) # Assume the timestamp is in the first 15 characters
    cmd = "date -d \"" timestamp "\" +%s"
    cmd | getline log_time
    close(cmd)

    # Only examine entries within the TIME_FRAME
    if ((current_time - log_time) <= time_frame) {
      # Extract IP from syslog entry and count occurrences
      match($0, /([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/, ip)
      if (ip[1] != "") ip_counts[ip[1]]++
    }
  }

  END {
    # Print suspicious IPs exceeding the threshold
    for (ip in ip_counts) {
      if (ip_counts[ip] >= threshold) print ip
    }
  }
  ' "$LOG_FILE"
}

# Main script logic
suspicious_ips=$(detect_port_scan)
if [[ ! -z "$suspicious_ips" ]]; then
  for ip in $suspicious_ips; do
    # Check if IP is already blocked to avoid duplicate blocks
    if ! grep -q "$ip" "$BLOCKED_IP_FILE"; then
      block_ip "$ip"
    else
      echo "IP $ip is already blocked."
    fi
  done
else
  echo "No suspicious activity detected."
fi
