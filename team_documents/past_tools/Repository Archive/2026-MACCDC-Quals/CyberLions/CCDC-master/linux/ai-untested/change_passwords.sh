#!/bin/bash
#
# This script changes the password for all non-system users.
# It can be run in two modes: interactive and non-interactive.
#
# Usage: ./change_passwords.sh [interactive|non-interactive]
#
# interactive: Prompts for a new password for each user.
# non-interactive: Generates a random password for each user and logs it.
#

LOG_FILE="password_changes.log"

# Function to generate a random password
generate_password() {
    tr -dc 'A-Za-z0-9!"#$%&'\''()*+,-./:;<=>?@[\]^_`{|}~' < /dev/urandom | head -c 16
}

# Get all non-system users (UID >= 1000)
users=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd)

if [ "$1" == "interactive" ]; then
    for user in $users; do
        echo "Changing password for $user"
        passwd "$user"
    done
elif [ "$1" == "non-interactive" ]; then
    echo "Changing passwords non-interactively. New passwords will NOT be logged for security reasons."
    for user in $users; do
        new_pass=$(generate_password)
        echo "$user:$new_pass" | chpasswd
        if [ $? -eq 0 ]; then
            echo "Successfully changed password for $user"
        else
            echo "Failed to change password for $user"
        fi
    done
else
    echo "Usage: $0 [interactive|non-interactive]"
    exit 1
fi

echo "Password changes complete."
