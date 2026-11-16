#!/bin/bash
#
# This script clones key system directories to a separate location.
# This is useful for creating a "live" snapshot for analysis without
# modifying the original files. It uses rsync for efficient copying.
#

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root to access all files." >&2
    exit 1
fi

# Directories to clone
# These are directories with important configuration files.
DIRS_TO_CLONE=(
    "/etc"
    "/var/www"
    "/usr/local/etc"
    "/var/spool/cron"
)

# Destination for the clones
DEST_DIR="/var/clone_backup"
echo "Cloning key directories to ${DEST_DIR}"
mkdir -p "${DEST_DIR}"

# --- Use rsync to clone the directories ---
echo "[*] Starting the cloning process..."
for DIR in "${DIRS_TO_CLONE[@]}"; do
    if [ -d "$DIR" ]; then
        echo "Cloning ${DIR}..."
        # Using -a to preserve permissions, ownership, etc.
        # Using -v for verbose output.
        # The trailing slash on the source directory is important.
        # It copies the content of the directory, not the directory itself.
        rsync -av --delete "${DIR}/" "${DEST_DIR}/$(basename ${DIR})/"
    else
        echo "Warning: Directory ${DIR} does not exist. Skipping."
    fi
done

echo "[+] Cloning complete. Snapshots are in ${DEST_DIR}"
ls -l "${DEST_DIR}"
