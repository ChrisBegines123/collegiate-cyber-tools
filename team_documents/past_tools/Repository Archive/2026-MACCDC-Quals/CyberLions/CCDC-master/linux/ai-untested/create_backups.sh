#!/bin/bash

# A script to create backups of important configuration folders for CCDC competitions.
# This script is intended to be run on Debian, Ubuntu, or CentOS systems.

# Function to display usage information
usage() {
    echo "Usage: $0 [backup_destination]"
    echo "If backup_destination is not provided, it will default to /var/backups/"
    exit 1
}

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
fi

# Directories to be backed up.
# These directories are commonly used for system and application configurations.
BACKUP_DIRS=(
    "/etc"
    "/var/www"
    "/home"
    "/usr/local/etc"
    "/opt"
    "/srv"
    "/var/log"
    "/var/spool/cron"
    "/var/lib/docker"
    "/var/lib/mysql"
    "/var/lib/postgresql"
)

# Set backup destination
if [ -n "$1" ]; then
    BACKUP_DEST="$1"
else
    BACKUP_DEST="/var/backups"
fi

# Create backup destination if it doesn't exist
mkdir -p "$BACKUP_DEST"

# Create a timestamp for the backup file
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILENAME="ccdc_backup_${TIMESTAMP}.tar.gz"
BACKUP_FILE="${BACKUP_DEST}/${BACKUP_FILENAME}"

# Inform the user where the backup will be stored
echo "Backup destination: ${BACKUP_DEST}"
echo "Backup filename: ${BACKUP_FILENAME}"


# Create a filtered list of directories that actually exist
EXISTING_DIRS=()
for DIR in "${BACKUP_DIRS[@]}"; do
    if [ -d "$DIR" ]; then
        EXISTING_DIRS+=("$DIR")
    else
        echo "Warning: Directory ${DIR} does not exist. Skipping."
    fi
done

if [ ${#EXISTING_DIRS[@]} -eq 0 ]; then
    echo "No directories to back up. Exiting."
    exit 1
fi

echo "Starting backup of the following directories:"
for DIR in "${EXISTING_DIRS[@]}"; do
    echo " - $DIR"
done


echo "Starting backup..."
tar -czvf "${BACKUP_FILE}" "${EXISTING_DIRS[@]}"

# Verify the backup
if [ $? -eq 0 ]; then
    echo "Backup successful: ${BACKUP_FILE}"
    ls -lh "${BACKUP_FILE}"
else
    echo "Backup failed!"
    exit 1
fi

exit 0
