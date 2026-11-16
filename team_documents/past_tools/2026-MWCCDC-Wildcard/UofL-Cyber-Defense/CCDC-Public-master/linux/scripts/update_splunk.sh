#!/usr/bin/env nix
#! nix shell nixpkgs#bash nixpkgs#wget --command bash
# Author: Collin Dewey
# Description:
# 
# Usage:
# ./<Script_Name>

. $(dirname "$0")/helper.sh; if [ -z ${PUBLIC_KEY+x} ]; then exit 1; fi
root_check

# Blindly assume SPLUNK_HOME is /opt/splunk
cp -r /opt/splunk /opt/splunk-orig
encrypt /opt/splunk-orig
systemctl stop splunk

# Reset the password while we're at it
PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)

echo $PASS > /opt/ccdc/splunk_pass
chown_ccdc /opt/ccdc/splunk_pass

echo '''[user_info]
USERNAME = admin
PASSWORD = $PASS
''' > /opt/splunk/etc/system/local/user-seed.conf

web wget -qO - https://splunk.com/en_us/download/splunk-enterprise.html | grep -o 'data-link="[^"]*64\.tgz"' | sed 's/data-link="//g; s/"//g' | xargs web wget -qO - | tar -xzv -C /opt
/opt/splunk/bin/splunk start --accept-license --answer-yes &
