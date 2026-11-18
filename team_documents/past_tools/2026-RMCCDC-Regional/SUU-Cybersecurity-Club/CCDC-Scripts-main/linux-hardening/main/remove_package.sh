#!/usr/bin/env bash

function remove_package() {
    local package_manager="$1"
    if [[ -z "$package_manager" ]]; then
        echo "No package manager provided to remove package :("
        exit 1
    fi

    local package_name="$2"
    if [[ -z "$package_name" ]]; then
        echo "No package name provided to remove package :("
        exit 1
    fi

    if [[ "$package_manager" == "unsupported" ]]; then
        echo "Unsupported operating system :("
        exit 1
    fi

    case "$package_manager" in
        apt)
            echo "Using apt to remove $package_name..."
            apt remove -y "$package_name"
            ;;
        dnf)
            echo "Using dnf to remove $package_name..."
            dnf remove -y "$package_name"
            ;;
        yum)
            echo "Using yum to remove $package_name..."
            yum remove -y "$package_name"
            ;;
        pacman)
            echo "Using pacman to remove $package_name..."
            pacman -R --noconfirm "$package_name"
            ;;
        zypper)
            echo "Using zypper to remove $package_name..."
            zypper remove -y "$package_name"
            ;;
        *)
            echo "Unsupported package manager :("
            exit 1
            ;;
    esac
}
