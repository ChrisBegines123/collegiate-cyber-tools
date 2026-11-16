#!/bin/bash 
# ==============================================================================
# Script Name : ubuntuwebharden.sh
# Description : Configure everything from A to B for Ubuntu 18.04 Web Server
# Author      : Tyler Olson
# Organization: Missouri State University
# ==============================================================================
# Usage       : ubuntuwebharden.sh
# Notes       :
#   - Make sure to update the variables as needed to configure the system correctly.
# ==============================================================================
# Changelog:
#   v1 - Adapted from Fedora script to Ubuntu 18.04
# ==============================================================================

# Check if added as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root or with sudo privileges"
    exit 1
fi

# Definitions:
username='root'
newUsername='example'
services=("apache2" "httpd")
port=5312  # SSH port

RED=$'\e[0;31m'; GREEN=$'\e[0;32m'; YELLOW=$'\e[0;33m'; BLUE=$'\e[0;34m'; NC=$'\e[0m'  # Sets the colors in use throughout the code

# Functions:
notify() { echo -e "${RED}$1${NC}"; }

software() {
    echo -e "${YELLOW} Installing software required for this system${NC}"
    apt update
    apt install -y tmux aide ufw
    echo -e "${GREEN} Software function completed.${NC}"
}

passchange() {
    echo -e "${YELLOW}changing root password${NC}"
    passwd
    echo -e "${YELLOW}changing password of provided username${NC}"
    passwd $username
}

backup() {
    mkdir -p /root/backit /etc/backup/ /root/backit/binaries

    for service in "${services[@]}"; do
        if [ -d "/etc/$service" ]; then
            cp -r "/etc/$service" "/root/backit/"
            echo -e "${GREEN}Backed up /etc/$service${NC}"
        elif [ -f "/etc/$service.conf" ]; then
            cp "/etc/$service.conf" "/root/backit/"
            echo -e "${GREEN}Backed up /etc/$service.conf${NC}"
        else
            echo -e "${RED}Warning: No config found for $service${NC}"
        fi
    done

    rsync -av /usr/bin/ /root/backit/binaries/ --exclude "*.tmp"  # backup binaries
    tar -czvf /root/backit/in_hardening_backup.tar.gz \
    /root \
    /var/www/html \
    /etc/apache2 \
    /etc/cron* \
    /etc/passwd \
    /etc/group \
    /etc/shadow \
    /etc/sudoers* \
    /etc/hosts \
    /etc/hostname \
    /etc/aliases \
    /etc/systemd \
    /etc/apt \
    /etc/resolv.conf \
    /usr/share/apache2 \
    /srv/vmail \
    /etc/sysconfig

    echo -e "${YELLOW}Completed the backup${NC}"
}

malphp() {
    echo -e "${YELLOW}cleaning up php files${NC}\n\n"
    find / -type f -name "index.php" ! -path "/var/www/*" 2>/dev/null | while read -r file; do
        # Backup the file to /root/ with a timestamp
        backup_file="/root/$(basename "$file")_$(date +%F_%T)"
        cp "$file" "$backup_file"
        rm -f "$file"            # Remove the original file

        # Log the action
        echo -e "${YELLOW}Removed malicious PHP file: $file (Backed up at $backup_file)${NC}"
    done
    echo "${YELLOW}cleaned up any php${NC}"
}

findcron() {
    echo -e "${YELLOW}Scanning for crontab entries...${NC}"

    # Locations to check
    locations=("/etc/crontab" "/etc/cron.d/*" "/var/spool/cron/crontabs/*" "/etc/cron.hourly/*" "/etc/cron.daily/*" "/etc/cron.weekly/*" "/etc/cron.monthly/*" "/etc/anacrontab")

    # Loop through each location
    for loc in "${locations[@]}"; do
        if [ -f "$loc" ] || [ -d "$loc" ]; then
            content=$(cat "$loc" 2>/dev/null)
            if [ -n "$content" ]; then
                echo -e "\n${RED}--- Found crontab at: $loc ---${NC}"
                echo "$content"
            fi
        fi
    done

    for user in $(cut -d: -f1 /etc/passwd); do
        cronfile="/var/spool/cron/crontabs/$user"
        if [ -f "$cronfile" ]; then
            content=$(cat "$cronfile" 2>/dev/null)
            if [ -n "$content" ]; then
                echo -e "\n--- User crontab for $user at: $cronfile ---"
                echo "$content"
                echo -e "${GREEN}\n --- Crontab finished printing ---${NC}"
            fi
        fi
    done

    echo -e "${GREEN}crontab scan complete.${NC}"
}

firewall_config() {
    echo -e "${YELLOW}--- Starting to configure firewall rules ---${NC}"
    
    # Ensure UFW is installed and enabled
    apt install -y ufw
    ufw --force enable
    
    # Reset to defaults
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow necessary services
    ufw allow 80/tcp    # HTTP
    ufw allow 443/tcp   # HTTPS  
    ufw allow $port/tcp # Custom SSH port
    ufw allow 323/tcp   # Chronyd (NTP)
    
    # Logging
    ufw logging on
    
    # Reload firewall
    ufw reload || notify "failed to reload ufw" >&2
    
    # List rules
    echo -e "${YELLOW}------------${NC}"
    echo -e "${BLUE}firewall rules:${NC}"
    ufw status verbose
    echo -e "${YELLOW}------------${NC}"
}

check_services() {
    local service=$1
    local port=$2

    if nc -z localhost $port; then
        echo "$service is running on port $port."
    else
        notify "failed to find $service running, attempting to start it"
        systemctl start $service || notify "service $service failed to start, check its logs and restore it" >&2
    fi
}

ssh_config() {
    # Needed SSH Config Files
    local SSHD_CONFIG_DIR="/etc/ssh/"
    local SSHD_CONFIG="/etc/ssh/sshd_config"

    # Ensure sshd_config.d directory exists
    mkdir -p "$SSHD_CONFIG_DIR"
    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.backup"
    # Set permissions
    chmod 444 "$SSHD_CONFIG"

    sed -i \
      -e "s/^[# ]*Port.*/Port $port/" \
      -e 's/^[# ]*PasswordAuthentication.*/PasswordAuthentication no/' \
      -e 's/^[# ]*PermitRootLogin.*/PermitRootLogin no/' \
      -e 's/^[# ]*PubkeyAuthentication.*/PubkeyAuthentication yes/' \
      -e 's/^[# ]*X11Forwarding .*/X11Forwarding no/' \
      -e 's/^[# ]*MaxAuthTries .*/MaxAuthTries 3/' \
      -e 's/^[# ]*ClientAliveMaxCount .*/ClientAliveMaxCount 2/' \
      "$SSHD_CONFIG"

    systemctl restart ssh
    echo "Configuring SSH daemon..."

    # Test configuration to see if there was errors
    if ! sshd -t ; then
        echo "Error: Invalid SSHD configuration"
        echo "Rolling back changes..."
        if [ -f "${SSHD_CONFIG}.backup" ]; then
            mv "${SSHD_CONFIG}.backup" "$SSHD_CONFIG"
        fi
        exit 1
    fi
}

fail2ban_setup() {
    echo -e "${YELLOW}Setting up fail2ban...${NC}"
    apt install -y fail2ban
    
    # Configure fail2ban
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    
    # Edit configuration to protect SSH with custom port
    cat > /etc/fail2ban/jail.d/ssh-custom.conf << EOF
[sshd]
enabled = true
port = $port
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF
    
    # Restart fail2ban
    systemctl restart fail2ban
    systemctl enable fail2ban
    
    echo -e "${GREEN}fail2ban installed and configured.${NC}"
}

main() {
    software
    passchange
    backup
    malphp
    findcron
    firewall_config
    ssh_config
    fail2ban_setup
    
    # Test service status
    check_services "apache2" "80"
    check_services "ssh" "$port"
    
    echo -e "\n----\n${GREEN}completed all basic hardening${NC}"
    echo -e "${YELLOW}Please now run AdvHardening for your distro${NC}"
    echo "${YELLOW}and don't forget to change the password${NC}"
}

main