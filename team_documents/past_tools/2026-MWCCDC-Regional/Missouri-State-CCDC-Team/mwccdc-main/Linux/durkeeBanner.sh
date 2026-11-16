#!/bin/bash
# ==============================================================================
# Script Name : durkeeBanner.sh
# Description : Durkee Banner
# Author      : Tyler Olson
# Organization: Missouri State University
# Version     : 1.2 -- durke 2.0
# ==============================================================================
# Credit to SpecialNebulae for this gem of a message

# Taking a backup of existing /etc/issue files
backup_existing_files() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    for file in "/etc/issue" "/etc/issue.net" "/etc/motd"; do
        if [ -f "$file" ]; then
            sudo cp "$file" "${file}.backup_${timestamp}"
            echo "Backed up $file to ${file}.backup_${timestamp}"
        fi
    done
}

# Function to validate if user has root privileges
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "This script must be run as root or with sudo privileges"
        exit 1
    fi
}

# Function to create banner content
create_banner() {
    cat << 'EOF' > /tmp/banner_content
╔════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ ║
║ ░                                                                                                                ░ ║
║ ░  Did you ever hear the tragedy of Darth Durkee the Wise?                                                       ░ ║
║ ░  I thought not. It’s not a story the Red Team would tell you.                                                  ░ ║
║ ░  It’s a Sith legend. Darth Durkee was a Dark Lord of the Sith,                                                 ░ ║
║ ░  so powerful and so wise he could use the Force to influence the packets to create life…                       ░ ║
║ ░  He had such a knowledge of the dark side that he could even keep the servers he cared about from Nyan Catted. ░ ║
║ ░  The dark side of the Force is a pathway to many abilities some consider to be unnatural.                      ░ ║
║ ░  He became so powerful… the only thing he was afraid of was losing his power,                                  ░ ║
║ ░  which eventually, of course, he did. Unfortunately, he taught his apprentice everything he knew,              ░ ║
║ ░  then his apprentice killed his server in his sleep. Ironic.                                                   ░ ║
║ ░  He could save others' servers from death, but not his.                                                        ░ ║
║ ░                                                                                                                ░ ║
║ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ ║
╚════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
EOF
}

# Function to implement the banner
implement_banner() {
    local banner_content="/tmp/banner_content"
    
    # Apply to local console login
    sudo cp "$banner_content" /etc/issue
    
    # Apply to SSH login
    sudo cp "$banner_content" /etc/issue.net
    
    # Apply to post-login message
    sudo cp "$banner_content" /etc/motd
    
    # Configure SSH to show banner
    if ! grep -q "^Banner /etc/issue.net" /etc/ssh/sshd_config; then
        echo "Banner /etc/issue.net" | sudo tee -a /etc/ssh/sshd_config
    fi
}

# Function to set proper permissions
set_permissions() {
    sudo chmod 644 /etc/issue
    sudo chmod 644 /etc/issue.net
    sudo chmod 644 /etc/motd
}

# Function to restart SSH service
restart_ssh() {
    if command -v systemctl &> /dev/null; then
        sudo systemctl restart sshd
    else
        sudo service sshd restart
    fi
}

# Main execution
main() {
    echo "Starting banner implementation..."
    
    # Check for root privileges
    check_root
    
    # Backup existing files
    backup_existing_files
    
    # Create and implement banner
    create_banner
    implement_banner
    
    # Set correct permissions
    set_permissions
    
    # Restart SSH service
    restart_ssh
    
    echo "Banner implementation completed successfully!"
    echo "Please test the banner by logging in through a new session."
    
    # Cleanup
    rm -f /tmp/banner_content
}

# Execute main function
main