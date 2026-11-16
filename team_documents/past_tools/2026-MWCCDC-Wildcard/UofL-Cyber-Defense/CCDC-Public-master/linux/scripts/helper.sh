#!/usr/bin/env bash
# Author: Collin Dewey
# Description:
# Helper functions
# Usage:
# . $(dirname "$0")/helper.sh; if [ -z ${PUBLIC_KEY+x} ]; then exit 1; fi

PUBLIC_KEY=age16r0xhfs07tr83qeu0a76x99pyds68sj2wn7yl34l0v5qenfplaaq803cnz
export PATH=$PATH:/sbin # Debian doesn't have /sbin by default in the path. Agony.

function create_user {
	if ! id "$1" >/dev/null 2>&1; then
		if [ -z "$2" ]; then
			useradd "$1" -s /usr/sbin/nologin -N -M
		else
			useradd "$1" -s /usr/sbin/nologin -N -M -g "$2"
		fi
	fi
}

function create_group {
	if ! getent group "$1" >/dev/null 2>&1; then
		groupadd "$1"
	fi
}

function download_unsafe {
	if command -v wget &> /dev/null; then
		web wget -q -O "$2" "$1" --no-check-certificate
	elif command -v curl &> /dev/null; then
		web curl -sSL -o "$2" "$1" --insecure
	else
		echo "Install curl, or wget."
		exit 1
	fi
}

function interactive_quit {
    if [[ $- != *i* ]]; then # Not interactive
        exit 1
    else
        return 1
    fi
}

function download {
    if [ -z "$2" ]; then
        filename=$(basename "$1")
        set -- "$1" "$filename"
    fi

    download_unsafe "$1" "$2"

    if [ -f "$2" ]; then
        file_size=$(stat -c%s "$2")
        if [ ! "$file_size" -gt 0 ]; then
            echo "Download failed: File Empty"
            interactive_quit
        fi
    else
        echo "$2 download failed"
        interactive_quit
    fi
}

function root_check {
    if [[ $EUID -ne 0 ]]; then
        if [ -n "$1" ]; then
            echo "$1"
        else
            echo "This script must be run as root."
        fi
        interactive_quit
    fi
}

function chown_ccdc {
    if [[ $EUID -eq 0 ]]; then
        chown ccdc $1
    fi
}

function force_kill {
	root_check
	if command -v killall &> /dev/null; then
		killall -9 "$1" >/dev/null 2>&1
	else
		kill -9 "$(pidof $1)" >/dev/null 2>&1
	fi
}

function is_in_nix_shell {
  if echo "$PATH" | grep -qc '/nix/store'; then
    export IN_NIX_SHELL=impure
  else
    unset IN_NIX_SHELL
  fi
}

function nix_shell_guard {
	is_in_nix_shell
	if [[ -z "${IN_NIX_SHELL}" ]]; then
  		echo "You need to have Nix installed for this script"
  		interactive_quit
	fi
}

function web { # Eval is dumb
    root_check "Type y and press enter to use the internet" # Stupid way to get sg
    cmd="sg internet_out -c \"$@\""
    eval "$cmd"
}

function sudoweb { # Eval is dumb
    cmd="sg internet_out -c \"$@\""
    eval "sudo $cmd"
}

# Avoids segault when using sudo with Nix (May have been fixed?)
function nix_fix {
	root_check
	su root -c "$1"
}

function if_systemd {
    if [ $(ps -p 1 -o comm=) == "systemd" ]; then
	    "$@"
    fi
}

function encrypt {
    pushd $(dirname $1) > /dev/null
    if [ -f "/bin/nix" ]; then
        if [ -d "$1" ]; then
            tar -cvzf - "$1" | nix run nixpkgs#age -- -r $PUBLIC_KEY -o "$1.age" "$1"
        elif [ -f "$1" ]; then
            nix run nixpkgs#age -- -r $PUBLIC_KEY -o "$1.age" "$1"
        fi
    else 
        echo "Failed encryption - Install Nix"
    fi
    popd > /dev/null
}

function decrypt {
    echo "Please enter your private key:"
    read key
    loc=$(mktemp)
    echo "$key" > "$loc"

    pushd $(dirname $1) > /dev/null
    if [ -d "$1" ]; then
        nix run nixpkgs#age -- --identity $loc -d "$1.age" | tar -xvf -
    elif [ -f "$1" ]; then
        nix run nixpkgs#age -- --identity $loc -d "$1.age" > "$1"
    fi
    popd > /dev/null

    rm "$loc"
    unset key
}
