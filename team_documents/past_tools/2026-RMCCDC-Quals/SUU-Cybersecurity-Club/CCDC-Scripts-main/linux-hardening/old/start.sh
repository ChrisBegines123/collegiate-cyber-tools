#!/bin/bash

# start.sh

# Get OS

OS=$(#! /bin/bash

# Function to get the OS name
os_name() {
    if [ -f /etc/os-release ]; then
        # freedesktop.org and systemd
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    elif type lsb_release > /dev/null 2>&1; then
        # linuxbase.org
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        # For some versions of Debian/Ubuntu without lsb_release command
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VER=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        # Older Debian/Ubuntu/etc.
        OS=Debian
        VER=$(cat /etc/debian_version)
    else
        # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
        OS=$(uname -s)
        VER=$(uname -r)
    fi
    echo "$OS" | tr '[:upper:]' '[:lower:]'
}

os_name_result=$(os_name)
echo "$os_name_result")

echo $OS

# Get Package Manager

package_manager=$(#! /bin/bash

# Get the OS name lowercase
OS="$OS"
if [[ -z "$OS" ]]; then
    echo "Error: No OS name provided to install_package."
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
esac)

echo $package_manager

# Get Wazuh Manager

read -p "Enter the Wazuh manager IP: " Wazuh_IP

wazuh_command="./linux_wazuh_agent.sh $Wazuh_IP $package_manager"

# Install apps


    #! /bin/bash

install_package() {
    local package_manager="$1"
    if [[ -z "$package_manager" ]]; then
        echo "Error: No package manager provided to install_package."
        exit 1
    fi

    local package_name="$2"
    if [[ -z "$package_name" ]]; then
        echo "Error: No package name provided to install_package."
        exit 1
    fi

    if [[ "$package_manager" == "unsupported" ]]; then
        echo "Error: Unsupported operating system."
        exit 1
    fi

    case "$package_manager" in
        apt)
            echo "Using apt to install $package_name..."
            apt update && apt install -y "$package_name"
            ;;
        dnf)
            echo "Using dnf to install $package_name..."
            dnf install -y "$package_name"
            ;;
        yum)
            echo "Using yum to install $package_name..."
            yum install -y "$package_name"
            ;;
        pacman)
            echo "Using pacman to install $package_name..."
            pacman -Syu --noconfirm "$package_name"
            ;;
        zypper)
            echo "Using zypper to install $package_name..."
            zypper install -y "$package_name"
            ;;
        *)
            echo "Error: Unsupported package manager."
            exit 1
            ;;
    esac
}
    

install_package "$package_manager" "vim"

install_package "$package_manager" "tmux"

install_package "$package_manager" "nmap"

# Tmux

#! /bin/bash

tmux new-session -d -s start \; \
    # Create 'user' tab
    tmux rename-window -t start:0 user \; \
    split-window -h \; \
    # Create 'banner' tab
    tmux new-window -t start:1 -n 'banner' \; \
    split-window \; \
    split-window \; \
    select-pane -t 0 \; \
    send-keys 'vim /etc/ssh/sshd_config' C-m \; \
    select-pane -t 1 \; \
    send-keys 'vim /etc/issue.net' C-m \; \
    select-pane -t 2 \; \
    send-keys 'Banner /etc/issue.net in config and write issue' \; \
    # Create 'backup' tab
    tmux new-window -t start:2 -n 'backup' \; \
    send-keys 'cd / && tar -cf ettc etc/' C-m \; \
    # Create 'install' tab
    tmux new-window -t start:3 -n 'install' \; \
    split-window -h \; \
    select-pane -t 1 \; \
    send-keys "$wazuh_command" C-m \; \
    select-pane -t 0 \; \
    send-keys 'nmap -sV -T4 -p- localhost > nmap.txt && less nmap.txt' C-m \; \
    # Set focus on the 'install' window and left pane
    tmux select-window -t start:0 \; \
    select-pane -t 0 \; \
    attach-session -t start