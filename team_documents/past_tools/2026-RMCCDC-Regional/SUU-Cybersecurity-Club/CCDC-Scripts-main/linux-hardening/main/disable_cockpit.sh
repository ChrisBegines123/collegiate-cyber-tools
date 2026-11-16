#!/usr/bin/env bash

source ./remove_package.sh
source ../first30.sh

function disable_cockpit() {
    systemctl stop cockpit 
    systemctl disable cockpit
    remove_package "$package_manager" "cockpit"
}
