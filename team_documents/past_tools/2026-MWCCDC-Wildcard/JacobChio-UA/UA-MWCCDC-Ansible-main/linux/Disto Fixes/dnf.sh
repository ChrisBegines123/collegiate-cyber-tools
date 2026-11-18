#!/usr/bin/env bash
set -euo pipefail

# Detect RHEL-family distributions and ensure `dnf` is available.
# Tries: use existing `dnf`, fall back to `yum`, then an `rpm`-based bootstrap.

log() { printf "%s\n" "$*"; }
err() { printf "ERROR: %s\n" "$*" >&2; }

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
	SUDO=sudo
else
	SUDO=
fi

# Gather OS info
OS_ID=""
OS_ID_LIKE=""
VERSION_ID=""
if [ -r /etc/os-release ]; then
	# shellcheck disable=SC1091
	. /etc/os-release
	OS_ID=${ID:-}
	OS_ID_LIKE=${ID_LIKE:-}
	VERSION_ID=${VERSION_ID:-}
fi

os_like_lc=$(printf "%s" "${OS_ID_LIKE:-}${OS_ID:-}" | tr '[:upper:]' '[:lower:]')

is_rhel_family=false
if [ -f /etc/redhat-release ] || printf "%s" "$os_like_lc" | grep -Eq 'rhel|fedora|centos|rocky|almalinux'; then
	is_rhel_family=true
fi

if [ "$is_rhel_family" != true ]; then
	err "This script only supports RHEL-family distributions. Detected: ID='${OS_ID:-unknown}', ID_LIKE='${OS_ID_LIKE:-unknown}'"
	exit 2
fi

if command -v dnf >/dev/null 2>&1; then
	log "dnf is already installed: $(command -v dnf)"
	exit 0
fi

log "dnf not found. Attempting to ensure dnf on RHEL-family distro..."

# If yum is present, prefer using it to install dnf
if command -v yum >/dev/null 2>&1; then
	log "Using yum to install dnf (non-interactive)..."
	$SUDO yum -y install dnf || {
		err "yum failed to install dnf";
		# continue to attempt rpm-based bootstrap
	}
	if command -v dnf >/dev/null 2>&1; then
		log "dnf installed successfully: $(command -v dnf)"
		exit 0
	fi
fi

# At this point, neither dnf nor yum installed. Attempt rpm-based bootstrap.
if ! command -v rpm >/dev/null 2>&1; then
	err "rpm is not available; cannot proceed with rpm-based installation."
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

# Determine arch and version
ARCH=$(uname -m || true)
MAJOR_VER="${VERSION_ID%%.*}"
MAJOR_VER=${MAJOR_VER:-8}

# Determine a suitable mirror base depending on distro
MIRROR=""
case "${OS_ID:-}" in
centos)
	MIRROR="https://mirror.centos.org/centos/${MAJOR_VER}/BaseOS/${ARCH}/os"
	;;
rocky)
	MIRROR="https://dl.rockylinux.org/pub/rocky/${MAJOR_VER}/BaseOS/${ARCH}/os"
	;;
almalinux)
	MIRROR="https://repo.almalinux.org/almalinux/${MAJOR_VER}/BaseOS/${ARCH}/os"
	;;
fedora)
	MIRROR="https://download.fedoraproject.org/pub/fedora/linux/releases/${MAJOR_VER}/Everything/${ARCH}/os"
	;;
ol)
	MIRROR="https://yum.oracle.com/repo/OracleLinux/OL${MAJOR_VER}/baseos/latest/${ARCH}"
    ;;
rhel)
	MIRROR="https://mirror.centos.org/centos/${MAJOR_VER}/BaseOS/${ARCH}/os"
	;;
*)
	MIRROR="https://mirror.centos.org/centos/${MAJOR_VER}/BaseOS/${ARCH}/os"
	;;
esac

log "Using mirror base: $MIRROR (os: ${OS_ID:-unknown} ver: ${MAJOR_VER} arch: ${ARCH})"

# Ensure there is at least one repo file under /etc/yum.repos.d
if ! ls /etc/yum.repos.d/*.repo >/dev/null 2>&1; then
	backup_dir="/etc/yum.repos.d/backup-$(date +%s)"
	$SUDO mkdir -p "$backup_dir" || true
	$SUDO mv /etc/yum.repos.d/*.repo "$backup_dir" 2>/dev/null || true
	log "No repo files found; creating a minimal repo file (backup moved to $backup_dir)"
	case "${OS_ID:-}" in
	centos|rhel)
		cat <<EOF | $SUDO tee /etc/yum.repos.d/00-bootstrap.repo >/dev/null
[bootstrap-base]
name=Bootstrap BaseRepo
baseurl=${MIRROR}
enabled=1
gpgcheck=0
EOF
		;;
	rocky)
		cat <<EOF | $SUDO tee /etc/yum.repos.d/00-bootstrap.repo >/dev/null
[bootstrap-base]
name=Bootstrap BaseRepo
baseurl=${MIRROR}
enabled=1
gpgcheck=0
EOF
		;;
	almalinux)
		cat <<EOF | $SUDO tee /etc/yum.repos.d/00-bootstrap.repo >/dev/null
[bootstrap-base]
name=Bootstrap BaseRepo
baseurl=${MIRROR}
enabled=1
gpgcheck=0
EOF
		;;
	fedora)
		cat <<EOF | $SUDO tee /etc/yum.repos.d/00-bootstrap.repo >/dev/null
[bootstrap-base]
name=Bootstrap BaseRepo
baseurl=${MIRROR}
enabled=1
gpgcheck=0
EOF
		;;
	*)
		cat <<EOF | $SUDO tee /etc/yum.repos.d/00-bootstrap.repo >/dev/null
[bootstrap-base]
name=Bootstrap BaseRepo
baseurl=${MIRROR}
enabled=1
gpgcheck=0
EOF
		;;
	esac
fi

tmpdir=$(mktemp -d)
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

repomd_url="$MIRROR/repodata/repomd.xml"
log "Fetching repomd: $repomd_url"
if ! $DL "$repomd_url" > "$tmpdir/repomd.xml"; then
	err "Failed to download repomd.xml from $repomd_url"
	# fallthrough to try yum/dnf if they appear later
fi

# parse repomd.xml for primary location
primary_href=$(grep -Ezo '<data[^>]*type="primary"[\s\S]*?<location href="[^"]+"' "$tmpdir/repomd.xml" 2>/dev/null | sed -n 's/.*href="\([^"]\+\)".*/\1/p' | head -n1 || true)
if [ -z "$primary_href" ]; then
	# try a common default path
	primary_href="repodata/primary.xml.gz"
fi

primary_url="$MIRROR/$primary_href"
log "Fetching primary index: $primary_url"
if ! $DL "$primary_url" > "$tmpdir/primary.xml.gz"; then
	err "Failed to download primary.xml.gz from $primary_url"
fi

# decompress
if [ -s "$tmpdir/primary.xml.gz" ]; then
	if command -v zcat >/dev/null 2>&1; then
		zcat "$tmpdir/primary.xml.gz" > "$tmpdir/primary.xml" || true
	elif command -v gzip >/dev/null 2>&1; then
		gzip -dc "$tmpdir/primary.xml.gz" > "$tmpdir/primary.xml" || true
	elif command -v python3 >/dev/null 2>&1; then
		python3 -c "import gzip,sys;sys.stdout.buffer.write(gzip.open(sys.argv[1],'rb').read())" "$tmpdir/primary.xml.gz" > "$tmpdir/primary.xml" || true
	fi
fi

# find rpm filename for package 'dnf'
rpm_href=""
if [ -s "$tmpdir/primary.xml" ]; then
	rpm_href=$(awk '/<package type="rpm">/{p=1} p{ if($0 ~ /<name>/ && $0 ~ /<\/name>/ && $0 ~ /<name>dnf<\/name>/){found=1} if(found && $0 ~ /<location href=/){gsub(/.*href="|".*/,"",$0); print $0; exit} }' "$tmpdir/primary.xml" | head -n1 || true)
fi

if [ -z "$rpm_href" ]; then
	# Try to guess package path under Packages/
	rpm_guess=$(ls "$tmpdir" >/dev/null 2>&1 || true)
	rpm_href="Packages/dnf-*.rpm"
fi

rpm_url="$MIRROR/$rpm_href"
rpm_file="$tmpdir/$(basename "$rpm_href")"

log "Attempting to download rpm: $rpm_url"
if ! $DL "$rpm_url" > "$rpm_file" 2>/dev/null; then
	err "Failed to download RPM from $rpm_url"
else
	log "Installing rpm: $rpm_file"
	if ! $SUDO rpm -Uvh --replacepkgs "$rpm_file" || true; then
		err "rpm install reported errors (continuing)"
	fi
fi

# After rpm attempt, try to use yum/dnf to fix deps
if command -v yum >/dev/null 2>&1; then
	log "Running 'yum -y install dnf' to finish installation and fix dependencies"
	$SUDO yum -y install dnf || log "yum install dnf failed (continuing)"
fi
if command -v dnf >/dev/null 2>&1; then
	log "dnf installed: $(command -v dnf)"
else
	err "Bootstrap attempt completed but 'dnf' is still missing. Manual intervention required."
	exit 11
fi

# Attempt to install helper packages
HELPERS=(dnf-plugins-core yum-utils ca-certificates curl wget rpm-build)
log "Attempting to install helper packages: ${HELPERS[*]}"
$SUDO dnf -y install "${HELPERS[@]}" || log "Installing helper packages via dnf failed"

log "dnf bootstrap complete"
exit 0
