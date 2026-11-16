#!/usr/env/bash

if (( EUID = 0 )); then
    echo Script cannot be ran as root!
    exit 1
fi

bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

souce /etc/profile
