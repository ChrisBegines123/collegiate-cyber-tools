#!/usr/bin/env bash
# Author: Collin Dewey
# Description:
# Incorrectly installs a third party package manager
# Usage:
# ./<Script_Name>
BRANCH="maintenance-2.24" # 2.25 and above changed the way packages are distributed through hydra. (Apparently that was a bug and is now fixed - see NixOS/nix#13078)

. $(dirname "$0")/helper.sh; if [ -z ${PUBLIC_KEY+x} ]; then exit 1; fi
root_check

mkdir -p /etc/nix

# Update System Certificates
download https://curl.se/ca/cacert.pem /etc/nix/ca-bundle.crt

# Download Nix
force_kill nix
download "https://hydra.nixos.org/job/nix/$BRANCH/buildStatic.nix.x86_64-linux/latest/download-by-type/file/binary-dist" /bin/nix 

# Configure
chmod +x /bin/nix
echo "extra-experimental-features = nix-command flakes auto-allocate-uids configurable-impure-env
ssl-cert-file = /etc/nix/ca-bundle.crt
auto-allocate-uids = true
use-xdg-base-directories = true
build-users-group = " > /etc/nix/nix.conf

# Create SystemD Service
if command -v systemctl >/dev/null 2>&1; then
    echo "
[Unit]
Description=Nix Daemon

[Service]
Type=simple
ExecStart=/bin/nix daemon
Group=internet_out

[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/nix-daemon.service
    systemctl daemon-reload
    systemctl enable nix-daemon.service # "enable --now" wasn't a thing on older versions of SystemD
    systemctl start nix-daemon.service
    sleep 2 # Icky
fi

# Pin
web nix registry pin github:NixOS/nixpkgs/nixos-unstable

# Copy closure if exists
if [ -d "/opt/ccdc/closure" ]; then
    /bin/nix copy --from /opt/ccdc/closure
    rm -rf /opt/ccdc/closure
fi

# Setup Comma
rc="/dev/null"
if [ -f "/etc/bashrc" ]; then
    rc="/etc/bashrc"
elif [ -f "/etc/bash.bashrc" ]; then
    rc="/etc/bash.bashrc"
fi

if ! grep -q "nix" $rc; then
    echo ". $(dirname "$0")/helper.sh" >> $rc
    echo 'alias update,="mkdir -p ~/.cache/nix-index; download https://github.com/Mic92/nix-index-database/releases/latest/download/index-x86_64-linux ~/.cache/nix-index/files; chown -R "$UID" ~/.cache/nix-index"' >> $rc
    echo 'alias ,="web nix run nixpkgs#comma --"' >> $rc
fi
