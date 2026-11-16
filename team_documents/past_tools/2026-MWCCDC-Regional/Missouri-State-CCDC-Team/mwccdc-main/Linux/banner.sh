#!/bin/bash
# ==============================================================================
# Script Name : banner.sh
# Description : This script will create login baners based on given content.
# Author      : Tyler Olson
# Organization: Missouri State University
# Version     : 1.1.1
# ==============================================================================
# Usage       : ./banner.sh
# Notes       :
#   - Made sure to make tihs to make it easy to implement a banner across the system.
# ==============================================================================


# Function to backup existing banner files
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
******************************************************************************
*                                                                            *
*                            AUTHORIZED ACCESS ONLY                          *
*                                                                            *
* This system is restricted to authorized users for legitimate business      *
* purposes only. All activities are monitored and recorded. Unauthorized     *
* access is prohibited and violators will be prosecuted to the full extent   *
* of applicable law.                                                         *
*                                                                            *
* By continuing to use this system, you indicate your awareness of and       *
* consent to these terms and conditions of use.                              *
*                                                                            *
******************************************************************************
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