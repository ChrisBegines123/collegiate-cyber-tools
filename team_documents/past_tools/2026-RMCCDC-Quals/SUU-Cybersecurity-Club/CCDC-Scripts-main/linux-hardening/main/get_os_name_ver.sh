#!/usr/bin/env bash

function get_os_name_ver() {
    if [ -f /etc/os-release ]; then
        # freedesktop.org and systemd
        . /etc/os-release
        declare -g OS="$NAME"
        declare -g VER="$VERSION_ID"
    elif type lsb_release > /dev/null 2>&1; then
        # linuxbase.org
        declare -g OS
        declare -g VER
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        # For some versions of Debian/Ubuntu without lsb_release command
        . /etc/lsb-release
        declare -g OS="$DISTRIB_ID"
        declare -g VER="$DISTRIB_RELEASE"
    elif [ -f /etc/debian_version ]; then
        # Older Debian/Ubuntu/etc.
        declare -g OS=Debian
        declare -g VER
        VER=$(cat /etc/debian_version)
    else
        # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
        declare -g OS
        declare -g VER
        OS=$(uname -s)
        VER=$(uname -r)
    fi
}
