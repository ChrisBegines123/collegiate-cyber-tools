#!/bin/bash

# --- CONFIGURATION ---
BACKUP_ROOT="/system_backup"
# ---------------------

# 1. Input Validation
if [ -z "$1" ]; then
    echo "Usage: sudo ./check_restore.sh /path/to/check"
    echo "Example: sudo ./check_restore.sh /etc/passwd"
    exit 1
fi

TARGET_PATH="$1"
# Strip trailing slash to ensure path consistency
TARGET_PATH="${TARGET_PATH%/}"
# Construct the path to the backup file
BACKUP_PATH="${BACKUP_ROOT}${TARGET_PATH}"

# 2. Check if the backup exists
if [ ! -e "$BACKUP_PATH" ]; then
    echo "Could not find $TARGET_PATH inside the backup folder."
    echo "Looked in: $BACKUP_PATH"
    echo "Run the full_backup.sh script first"
    exit 1
fi

echo "Checking integrity of: $TARGET_PATH"
echo "----------------------------------------"

# 3. Compare using diff
# -r = recursive, -q = quiet (just yes/no)
if diff -rq "$TARGET_PATH" "$BACKUP_PATH" > /dev/null; then
    echo "No changes detected."
    exit 0
else
    echo "CHANGES DETECTED!"
    echo "The live file is different from the backup."
    echo ""
    
    # 4. Prompt for Restore
    read -p "Do you want to OVERWRITE the live version with the backup? (y/N): " choice
    case "$choice" in 
        y|Y ) 
            echo "Restoring..."
            # -r = recursive, -v = verbose. 
            # cp simply copies the backup over the top. It does NOT delete extra files.
            # We use dirname to ensure we copy the file/folder INTO its parent directory.
            if [ -d "$TARGET_PATH" ]; then
                # If it's a directory, copy contents
                cp -rv "$BACKUP_PATH/." "$TARGET_PATH/"
            else
                # If it's a file, copy the file
                cp -v "$BACKUP_PATH" "$TARGET_PATH"
            fi
            
            echo "Done. Restore complete."
            ;;
        * ) 
            echo "Action cancelled. No changes made."
            ;;
    esac
fi
