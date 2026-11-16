#!/bin/bash

# Variables
LOG_FILE="/var/log/auth.log"      # Log file to monitor
THRESHOLD=5                       # Number of failed attempts to trigger blocking
BLOCKED_IP_FILE="./blocked_ips.log"  # File to keep track of blocked IPs

# Function to block an IP using iptables
block_ip() {
  local ip=$1
  echo "Blocking IP: $ip"
  iptables -A INPUT -s "$ip" -j DROP
  echo "$(date): Blocked IP $ip due to brute-force attempts" >> "$BLOCKED_IP_FILE"
}

# Function to detect brute-force attempts
detect_brute_force() {
  echo "Checking for SSH brute-force attempts..."
  
  # Parse the log file for failed login attempts
  awk '/Failed password/ {print $(NF-3)}' "$LOG_FILE" | sort | uniq -c | while read count ip; do
    if (( count > THRESHOLD )); then
      # Check if IP is already blocked to avoid duplicate blocks
      if ! grep -q "$ip" "$BLOCKED_IP_FILE"; then
        block_ip "$ip"
      else
        echo "IP $ip is already blocked."
      fi
    fi
  done
}

# Run the detection function
detect_brute_force
