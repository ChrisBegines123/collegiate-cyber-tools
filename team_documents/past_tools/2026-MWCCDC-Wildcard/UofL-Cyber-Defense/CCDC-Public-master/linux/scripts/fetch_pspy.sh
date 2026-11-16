#!/usr/bin/env bash
# Author: Collin Dewey
# Description:
# Downloads pspy
# Usage:
# ./<Script_Name>

. $(dirname "$0")/helper.sh; if [ -z ${PUBLIC_KEY+x} ]; then exit 1; fi

download https://github.com/DominicBreuker/pspy/releases/download/v1.2.1/pspy64 /opt/ccdc/pspy
chown_ccdc /opt/ccdc/pspy
chmod +x /opt/ccdc/pspy