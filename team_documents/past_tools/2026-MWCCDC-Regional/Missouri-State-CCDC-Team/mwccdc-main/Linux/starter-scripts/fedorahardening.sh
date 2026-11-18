#!/bin/bash 
# ==============================================================================
# Script Name : fedoraharden.sh
# Description : Configure everything from A to B
# Author      : Tyler Olson
# Organization: Missouri State University
# ==============================================================================
# Usage       : fedoraharden.sh
# Notes       :
#   - Make sure to update the variables as needed to configure the system correctly.
# ==============================================================================
# Changelog:
#   v1 - Major bug fixes and additions of colors to the file
#   v1.1 - SGVsbG8gZnJpZW5kLCB5b3Ugc2VlbSBsb3N0Pw==
# ==============================================================================

# Check if script is running as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root or with sudo privileges"
    exit 1
fi

# Definitions:
username='root'
newUsername='example'
services=("postfix" "dovecot")

RED=$'\e[0;31m'; GREEN=$'\e[0;32m'; YELLOW=$'\e[0;33m'; BLUE=$'\e[0;34m'; NC=$'\e[0m'       # Sets the colors in use throughout the code

# Functions:
notify() { echo -e "${RED}$1${NC}"; }

software() {
    echo -e "${YELLOW} Installing software required for this system${NC}"
    sudo yum update
    yum install -y tmux tripwire
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

    rsync -av /usr/bin/ /root/backit/binaries/ --exclude "*.tmp"       # backup binaries
    tar -czvf /root/backit/in_hardening_backup.tar.gz \
    /root \
    /var/www/html \
    /etc/roundcubemail \
    /etc/httpd \
    /etc/dovecot \
    /etc/postfix \
    /etc/cron* \
    /etc/passwd \
    /etc/group \
    /etc/shadow \
    /etc/sudoers* \
    /etc/hosts \
    /etc/hostname \
    /etc/aliases \
    /etc/systemd \
    /etc/yum* \
    /etc/resolv.conf \
    /usr/share/httpd \
    /srv/vmail \
    /etc/sysconfig \
    /usr/share/roundcubemail \
    /usr/share/dovecot

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
        echo -e "${YELLOW}Removed malicious PHP file: $file (Backed up at $backup_file)${NC}" >> /root/malphp.log
        echo -e "${YELLOW}Removed malicious PHP file: $file (Backed up at $backup_file)${NC}"
    done
    echo "${YELLOW}cleaned up any php${NC}"
}

findcron() {
    echo -e "${YELLOW}Scanning for crontab entries...${NC}"

    # Locations to check
    locations=("/etc/crontab" "/etc/cron.d/*" "/var/spool/cron/crontabs/*" "/var/spool/cron/*" "/etc/cron.hourly/*" "/etc/cron.daily/*" "/etc/cron.weekly/*" "/etc/cron.monthly/*" "/etc/anacrontab")

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
    sudo firewall-cmd --permanent --new-zone=ccdczone                               # Creating a new zone
    sudo firewall-cmd --set-default-zone=ccdczone                                   
    sudo firewall-cmd --permanent --zone=ccdczone --add-port=587/tcp                # Port for SMTP
    sudo firewall-cmd --permanent --zone=ccdczone --add-port=25/tcp                 # Ports for SMTP
    sudo firewall-cmd --permanent --zone=ccdczone --add-port=110/tcp                # Ports for Pop3
    sudo firewall-cmd --permanent --zone=ccdczone --add-port=995/tcp
    sudo firewall-cmd --permanent --zone=ccdczone --add-port=5312/tcp               # Adding ports for SSH
    sudo firewall-cmd --permanent --add-port=323/tcp                                # Chronyd (NTP)
    sudo firewall-cmd --permanent --zone=ccdczone --set-target=DROP                 # Explicitly deny traffic
    sudo firewall-cmd --reload || notify "failed to reload firewalld" >&2           # Reloading the firewall

    # Listing all the current rules for debugging.
    echo -e "${YELLOW}------------${NC}"
    echo -e "${BLUE}firewall rules:${NC}"
    firewall-cmd --list-all
    echo -e "${YELLOW}------------${NC}"
}

check_services() {
    local service=$1
    local port=$2

    if nc -z localhost $port; then
        echo "$service is running on port $port."
    else
        notify "failed to find $service running, attempting to start it"
        sudo systemctl start $service || notify "service $service failed to start, check its logs and restore it" >&2
    fi
}


### NEED TO ADD PUBLIC KEY ADDITION TO THIS FILE. 

ssh_config() {
    # Needed SSH Config Files
    local SSHD_CONFIG_DIR="/etc/ssh/"
    local SSHD_CONFIG="/etc/ssh/sshd_config"

    # Ensure sshd_config.d directory exists
    mkdir -p "$SSHD_CONFIG_DIR"
    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.backup"
    #Set permissions
    chmod 444 "$SSHD_CONFIG"

    sed -i \
      -e "s/^[# ]*Port.*/Port $port/" \
      -e 's/^[# ]*PasswordAuthentication.*/PasswordAuthentication no/' \
      -e 's/^[# ]*PermitRootLogin.*/PermitRootLogin no/' \
      -e 's/^[# ]*PubkeyAuthentication.*/PubkeyAuthentication yes/' \
      -e 's/^[# ]*X11[Ff]orwarding .*/X11Forwarding no/' \
      -e 's/^[# ]*MaxAuthTries .*/MaxAuthTries 3/' \
      -e 's/^[# ]*ClientAliveMaxCount .*//ClientAliveMaxCount 2/' \
      "$SSHD_CONFIG"

    systemctl restart ssh
    echo  "Configuring SSH daemon..."

    # Test configuration to see if there was errors
    if ! sshd -t ; then
        echo "Error: Invalid SSHD configuration"
        echo "Rolling back changes..."
        if [ -f "${SSHD_CONFIG}.backup" ]; then
            mv "${SSHD_CONFIG}.backup" "$SSHD_CONFIG"
        fi
        rm -f "$SSHD_CUSTOM_CONFIG"
        exit 1
    fi
}

main() {
    software
    passchange
    backup
    malphp
    findcron
    firewall_config
    check_services
    ssh_config

    echo -e "\n----\n${GREEN}completed all basic hardening${NC}"
    echo -e "${YELLOW}Please now run AdvHardening for your distro${NC}"
    echo "${YELLOW}and don't forget to change the password${NC}"
}

main