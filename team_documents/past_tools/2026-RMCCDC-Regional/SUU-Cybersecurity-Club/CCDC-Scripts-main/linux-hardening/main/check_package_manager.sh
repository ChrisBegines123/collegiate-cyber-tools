#!/usr/bin/env bash

function check_package_manager() {
    if [[ -z "$OS" ]]; then
        echo "Error: No OS name provided to remove_package."
        exit 1
    fi

    case "$OS" in
        ubuntu|debian)
            echo "apt"
            ;;
        centos|rocky|almalinux|fedora)
            echo "yum"
            ;;
        arch)
            echo "pacman"
            ;;
        opensuse*)
            echo "zypper"
            ;;
        *)
            echo "unsupported"
            ;;
    esac
}
