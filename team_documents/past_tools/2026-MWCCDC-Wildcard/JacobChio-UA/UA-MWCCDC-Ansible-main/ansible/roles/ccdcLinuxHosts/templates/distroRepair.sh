#!/usr/bin/env bash
set -euo pipefail

chmod +x "$(dirname "${BASH_SOURCE[0]}")/apt.sh" "$(dirname "${BASH_SOURCE[0]}")/dnf.sh"

# Simple driver: detect distro family and invoke apt.sh or dnf.sh

log() { printf "%s\n" "$*"; }
err() { printf "ERROR: %s\n" "$*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APT_SCRIPT="$SCRIPT_DIR/apt.sh"
DNF_SCRIPT="$SCRIPT_DIR/dnf.sh"

if [ -r /etc/os-release ]; then
	# shellcheck disable=SC1091
	. /etc/os-release
else
	err "Cannot read /etc/os-release; unknown distribution"
	exit 2
fi

os_like_lc=$(printf "%s" "${ID_LIKE:-}${ID:-}" | tr '[:upper:]' '[:lower:]')

is_debian=false
is_rhel=false

if [ -f /etc/debian_version ] || printf "%s" "$os_like_lc" | grep -Eq 'debian|ubuntu|raspbian|pop'; then
	is_debian=true
fi
if [ -f /etc/redhat-release ] || printf "%s" "$os_like_lc" | grep -Eq 'rhel|fedora|centos|rocky|almalinux'; then
	is_rhel=true
fi

if [ "$is_debian" = true ]; then
	if [ -x "$APT_SCRIPT" ]; then
		log "Detected Debian-family distro; running $APT_SCRIPT"
		exec "$APT_SCRIPT"
	elif [ -f "$APT_SCRIPT" ]; then
		log "Detected Debian-family distro; running $APT_SCRIPT with bash"
		exec bash "$APT_SCRIPT"
	else
		err "Missing script: $APT_SCRIPT"
		exit 3
	fi
fi

if [ "$is_rhel" = true ]; then
	if [ -x "$DNF_SCRIPT" ]; then
		log "Detected RHEL-family distro; running $DNF_SCRIPT"
		exec "$DNF_SCRIPT"
	elif [ -f "$DNF_SCRIPT" ]; then
		log "Detected RHEL-family distro; running $DNF_SCRIPT with bash"
		exec bash "$DNF_SCRIPT"
	else
		err "Missing script: $DNF_SCRIPT"
		exit 4
	fi
fi

err "Unsupported or unknown distribution (ID='${ID:-unknown}', ID_LIKE='${ID_LIKE:-unknown}')"
exit 5

