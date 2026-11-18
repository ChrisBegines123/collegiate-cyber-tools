#!/usr/bin/env bash
# Description:
# Performs various actions
# Usage:
# ./<SCRIPT NAME>

. $(dirname "$0")/helper.sh; if [ -z ${PUBLIC_KEY+x} ]; then exit 1; fi
root_check

# Rename a bunch of tools that might be useful
function move {
    if [ -f $1 ]; then
        mv "$1" "${1}.old"
    fi
}

# Executables
# move /bin/dd # This apparently breaks makeself
move /bin/dig
move /bin/base64
move /bin/at
move /bin/nc
move /bin/ncat

move /etc/ld.so.preload
# move /etc/ld.so.cache # Broke Ubuntu 16.04 for some reason
move /etc/inittab
touch /etc/inittab
chattr +i /etc/inittab

# Disable cron
move /usr/sbin/cron
cut -d: -f1 /etc/passwd | tail -n+2 >> /etc/cron.deny