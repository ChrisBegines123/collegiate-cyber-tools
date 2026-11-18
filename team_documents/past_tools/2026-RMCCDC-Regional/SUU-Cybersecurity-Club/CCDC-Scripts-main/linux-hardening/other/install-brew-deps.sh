#!/usr/bin/env bash

if (( EUID != 0 )); then
    echo "Script must be ran as root!"
    exit 1
fi

source ../main/get_os_name_ver.sh
source ../main/check_package_manager.sh
source ../main/install_package.sh

# Get os name and version
get_os_name_ver
echo "OS=$OS VER=$VER" > /dev/null 2>&1 

# Clean things up
OS="${OS,,}"

if [ "$OS" = "ubuntu" ]; then
    # Fix version to work with integer comparison
    VER="${VER::-3}"
elif [[ "$OS" =~ "fedora" ]]; then
    # Shorten Fedora Linux to fedora
    OS="fedora"
fi

export OS VER

package_manager=$(check_package_manager)

declare -a ubuntu_dependencies
declare -a fedora_dependencies

ubuntu_dependencies=( "build-essential" "procps" "curl" "file" "git" )
fedora_dependencies=( "diffstat" "doxygen" "gettext" "git" "patch" "patchutils" "subversion" "systemtap" "file" )

ubuntu_file_path="../binaries/brew/deb/"
fedora_file_path="../binaries/brew/rpm/"

brew_check() {
    which brew 

    check=$?

    if [ "$check" -ne "0" ]; then
        echo 'Brew is already installed, quitting...'

        exit 0
    fi
}

function install_brew_deps_ubuntu() {
    echo Installing dependencies

    for package in "${ubuntu_dependencies[@]}"; do
        install_package "$package_manager" "$package"
    done

    install_status=$?

    if [ "$install_status" -ne "0" ]; then
        echo "Default isntall did not work, attempting with pre-supplied archives..."
        
        for archive in "${ubuntu_dependencies[@]}"; do
            archive+="_ubuntu_22.04.deb"
            ubuntu_file_path+="$archive"
            install_package "$package_manager" "$archive"
        done
    fi

    install_status=$?

    if [ "$install_status" -ne "0" ]; then
        echo "Your dependencies are cooked pal, good luck"
        exit 1
    fi
}

function install_brew_deps_fedora() {
    echo Installing dependencies

    install_package "$package_manager" "${fedora_dependencies[*]}"

    install_status=$?

    if [ "$install_status" -ne "0" ]; then
        echo "Default isntall did not work, attempting with pre-supplied archives..."
        
        for archive in "${fedora_dependencies[@]}"; do
            archive+="_fedora_42.rpm"
            fedora_file_path+="$archive"
            install_package "$package_manager" "$archive"
        done
    fi

    install_status=$?

    if [ "$install_status" -ne "0" ]; then
        echo "Your dependencies are cooked pal, good luck"
        exit 1
    fi
}

case "$OS" in
    ubuntu|debian)
        install_brew_deps_ubuntu
        ;;
    centos|rocky|almalinux|fedora)
        install_brew_deps_fedora
        ;;
esac

echo 'export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"' > /etc/profile.d/brew-path.sh
