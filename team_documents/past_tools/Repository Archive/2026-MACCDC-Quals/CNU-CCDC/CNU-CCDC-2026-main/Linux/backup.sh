#!/usr/bin/env bash

set -euo pipefail

LOGNAME="backup_script.log"

logger() {
  text=$1
  echo "$1" >> ${LOGNAME}
}

echo "Backup script started"  # Log the start of the script
logger "Backup script started"  # Log the start of the script

rsync -ac config_dir @backup_host:/backup_dir # not done