#!/usr/bin/env bash

source ./remove_package.sh
source ../first30.sh

function configure_sshd() {
    flag="$1"
    if [ "$flag" = "true" ]; then
        # Disable for now, configure later
        systemctl stop sshd 
        systemctl disable sshd
        remove_package "$package_manager" "openssh-server"
    fi
}
