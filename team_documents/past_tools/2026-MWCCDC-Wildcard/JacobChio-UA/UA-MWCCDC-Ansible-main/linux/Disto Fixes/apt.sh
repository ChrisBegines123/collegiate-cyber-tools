#!/usr/bin/env bash
set -euo pipefail

# Detect Debian-family distributions and install `apt` if missing.
# Safe, non-interactive. Exits with non-zero on failure.

log() { printf "%s\n" "$*"; }
err() { printf "ERROR: %s\n" "$*" >&2; }

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
	SUDO=sudo
else
	SUDO=
fi

# Read os-release if available
OS_ID=""
OS_ID_LIKE=""
if [ -r /etc/os-release ]; then
	# shellcheck disable=SC1091
	. /etc/os-release
	OS_ID=${ID:-}
	OS_ID_LIKE=${ID_LIKE:-}
fi

os_like_lc=$(printf "%s" "${OS_ID_LIKE:-}${OS_ID:-}" | tr '[:upper:]' '[:lower:]')

is_debian_family=false
if [ -n "$(grep -Ei 'debian' /etc/os-release 2>/dev/null || true)" ] || [ -f /etc/debian_version ] || printf "%s" "$os_like_lc" | grep -Eq 'debian|ubuntu|raspbian|pop'; then
	is_debian_family=true
fi

if [ "$is_debian_family" != true ]; then
	err "This script only supports Debian or Debian-derivative distributions. Detected: ID='${OS_ID:-unknown}', ID_LIKE='${OS_ID_LIKE:-unknown}'"
	exit 2
fi

if command -v apt >/dev/null 2>&1; then
	log "apt is already installed: $(command -v apt)"
	exit 0
fi

log "apt not found. Attempting to install on Debian-family distro..."

if command -v apt-get >/dev/null 2>&1; then
	log "Using apt-get to install apt (non-interactive)..."
	export DEBIAN_FRONTEND=noninteractive
	$SUDO apt-get update -y || err "apt-get update failed"
	$SUDO apt-get install -y apt || {
		err "apt-get failed to install 'apt' package";
		exit 3
	}
	if command -v apt >/dev/null 2>&1; then
		log "apt installed successfully: $(command -v apt)"
		exit 0
	else
		err "Installation reported success but apt binary still missing"
		exit 4
	fi

else
	err "Neither 'apt' nor 'apt-get' are available. Attempting dpkg-based bootstrap..."

	if ! command -v dpkg >/dev/null 2>&1; then
		err "dpkg is not available; cannot proceed with dpkg-based installation."
		exit 5
	fi

	# choose download tool
	if command -v curl >/dev/null 2>&1; then
		DL="curl -fsSL"
	elif command -v wget >/dev/null 2>&1; then
		DL="wget -qO-"
	else
		err "Neither curl nor wget is available to download packages."
		exit 6
	fi

	# determine architecture and codename
	ARCH=$(dpkg --print-architecture 2>/dev/null || true)
	CODENAME=""
	if [ -n "${VERSION_CODENAME:-}" ]; then
		CODENAME=${VERSION_CODENAME}
	elif command -v lsb_release >/dev/null 2>&1; then
		CODENAME=$(lsb_release -sc 2>/dev/null || true)
	fi
	CODENAME=${CODENAME:-stable}

	# determine mirror from existing APT sources if possible
	MIRROR="https://deb.debian.org/debian"
	if [ -r /etc/apt/sources.list ]; then
		first_deb=$(grep -Eo '^deb\s+\S+' /etc/apt/sources.list | awk '{print $2}' | head -n1 || true)
		if [ -n "$first_deb" ]; then
			MIRROR=$first_deb
		fi
	fi

	log "Using mirror: $MIRROR (codename: $CODENAME, arch: $ARCH)"

	PACKAGES_URL="$MIRROR/dists/$CODENAME/main/binary-$ARCH/Packages.gz"

	tmpdir=$(mktemp -d)
	cleanup() { rm -rf "$tmpdir"; }
	trap cleanup EXIT

	log "Fetching Packages index to locate 'apt' package..."
	if ! $DL "$PACKAGES_URL" > "$tmpdir/Packages.gz"; then
		err "Failed to download Packages.gz from $PACKAGES_URL"
		exit 7
	fi

	if command -v zcat >/dev/null 2>&1; then
		zcat "$tmpdir/Packages.gz" > "$tmpdir/Packages" || { err "Failed to decompress Packages.gz"; exit 8; }
	elif command -v gzip >/dev/null 2>&1; then
		gzip -dc "$tmpdir/Packages.gz" > "$tmpdir/Packages" || { err "Failed to decompress Packages.gz"; exit 8; }
	elif command -v python3 >/dev/null 2>&1; then
		python3 -c "import gzip,sys;sys.stdout.buffer.write(gzip.open(sys.argv[1],'rb').read())" "$tmpdir/Packages.gz" > "$tmpdir/Packages" || { err "Failed to decompress Packages.gz with python3"; exit 8; }
	else
		err "No tool available to decompress Packages.gz (need zcat, gzip or python3)."
		exit 8
	fi

	# find the Filename for package 'apt'
	pkg_filename=$(awk '/^Package: apt$/,/^$/{ if ($1=="Filename:") print $2 }' "$tmpdir/Packages" | head -n1 || true)
	if [ -z "$pkg_filename" ]; then
		err "Could not find 'apt' package filename in Packages index."
		exit 9
	fi

	pkg_url="$MIRROR/$pkg_filename"
	pkg_file="$tmpdir/$(basename "$pkg_filename")"

	log "Downloading $pkg_url"
	if ! $DL "$pkg_url" > "$pkg_file"; then
		err "Failed to download $pkg_url"
		exit 10
	fi

	log "Installing $pkg_file via dpkg..."
	if ! $SUDO dpkg -i "$pkg_file"; then
		err "dpkg reported errors. Attempting to fix dependencies..."
	fi

	# Restore default repositories if sources.list has no active 'deb' entries
	if ! grep -E -v '^\s*#' /etc/apt/sources.list 2>/dev/null | grep -q '^deb\s' ; then
		backup="/etc/apt/sources.list.bak.$(date +%s)"
		$SUDO cp -a /etc/apt/sources.list "$backup" 2>/dev/null || true
		log "No active APT entries found; restoring minimal default repositories (backup: $backup)"
		case "${OS_ID:-debian}" in
		debian)
			cat <<-EOF | $SUDO tee /etc/apt/sources.list >/dev/null
		deb http://deb.debian.org/debian ${CODENAME} main contrib non-free
		deb http://security.debian.org/debian-security ${CODENAME}-security main contrib non-free
		deb http://deb.debian.org/debian ${CODENAME}-updates main contrib non-free
		EOF
			;;
		ubuntu)
			cat <<-EOF | $SUDO tee /etc/apt/sources.list >/dev/null
		deb http://archive.ubuntu.com/ubuntu ${CODENAME} main restricted universe multiverse
		deb http://archive.ubuntu.com/ubuntu ${CODENAME}-updates main restricted universe multiverse
		deb http://security.ubuntu.com/ubuntu ${CODENAME}-security main restricted universe multiverse
		EOF
			;;
		raspbian|raspberrypi)
			cat <<-EOF | $SUDO tee /etc/apt/sources.list >/dev/null
		deb http://raspbian.raspberrypi.org/raspbian/ ${CODENAME} main contrib non-free rpi
		EOF
			;;
		*)
			cat <<-EOF | $SUDO tee /etc/apt/sources.list >/dev/null
		deb http://deb.debian.org/debian ${CODENAME} main contrib non-free
		EOF
			;;
		esac
	fi

	# Try to update package lists and fix dependencies using apt-get/apt if available
	export DEBIAN_FRONTEND=noninteractive
	if command -v apt-get >/dev/null 2>&1; then
		log "Running apt-get update and fixing dependencies"
		$SUDO apt-get update -y || log "apt-get update failed (continuing)"
		$SUDO apt-get -f install -y || log "apt-get -f install failed (continuing)"
	fi

	# Attempt to install common helper dependencies to allow further package operations
	DEPS=(apt-utils ca-certificates gnupg wget curl lsb-release apt-transport-https)
	if command -v apt-get >/dev/null 2>&1; then
		log "Attempting to install helper packages: ${DEPS[*]}"
		$SUDO apt-get install -y "${DEPS[@]}" || log "Installing helper packages via apt-get failed"
	elif command -v apt >/dev/null 2>&1; then
		log "Attempting to install helper packages via apt: ${DEPS[*]}"
		$SUDO apt update || true
		$SUDO apt install -y "${DEPS[@]}" || log "Installing helper packages via apt failed"
	else
		log "No apt/apt-get available to install helper packages"
	fi

	if command -v apt >/dev/null 2>&1; then
		log "apt successfully installed: $(command -v apt)"
		exit 0
	else
		err "Bootstrap attempt completed but 'apt' is still missing. Manual intervention required."
		exit 11
	fi
fi

