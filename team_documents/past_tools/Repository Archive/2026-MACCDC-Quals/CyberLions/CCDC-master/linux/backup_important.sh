#!/bin/bash

# --- CONFIGURATION ---
BACKUP_DIR="/system_backup"
# ---------------------

# 1. Check if running as root
if [ "$EUID" -ne 0 ]; then 
  echo "Run as Root / Sudo"
  exit 1
fi

# 2. Check for rsync and install if missing
if ! command -v rsync &> /dev/null; then
    echo "rsync not found! Attempting to install it..."
    
    if [ -x "$(command -v apt-get)" ]; then
        apt-get update && apt-get install -y rsync
    elif [ -x "$(command -v dnf)" ]; then
        dnf install -y rsync
    elif [ -x "$(command -v yum)" ]; then
        yum install -y rsync
    elif [ -x "$(command -v apk)" ]; then
        apk add rsync
    elif [ -x "$(command -v pacman)" ]; then
        pacman -Sy --noconfirm rsync
    else
        echo "Could not detect package manager. Please install 'rsync' manually."
        exit 1
    fi
    
    # Double check installation worked
    if ! command -v rsync &> /dev/null; then
         echo "Installation failed. Exiting."
         exit 1
    fi
    echo "rsync installed successfully."
fi

# 3. Perform Backup
echo "Starting system backup to $BACKUP_DIR..."

mkdir -p "$BACKUP_DIR"

# -aAX: Archive mode + ACLs + Extended attributes
# -v: Verbose
# --exclude: Skips virtual dirs and the backup folder itself
rsync -aAXvW / "$BACKUP_DIR" \
    --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} \
    --exclude={"/usr/lib/*","/usr/share/*","/usr/src/*","/var/cache/*","/var/lib/*","/var/log/*"} \
    --exclude="$BACKUP_DIR"

echo "----------------------------------------"
echo "Backup complete. System stored in $BACKUP_DIR"
echo "----------------------------------------"
