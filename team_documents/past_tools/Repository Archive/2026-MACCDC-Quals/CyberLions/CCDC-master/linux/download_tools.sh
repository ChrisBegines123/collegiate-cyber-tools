#!/bin/bash
#
# This script downloads a collection of useful security tools for CCDC.
# Tools are downloaded to a specified directory, defaulting to /opt/tools.
#

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
fi

# Set the destination directory for tools
TOOLS_DIR="/opt/ccdc-tools"
echo "Tools will be downloaded to ${TOOLS_DIR}"
mkdir -p "${TOOLS_DIR}"
cd "${TOOLS_DIR}" || exit 1

# --- Tools to Download ---

# LinPEAS: Linux Privilege Escalation Awesome Script
echo "[*] Downloading LinPEAS..."
wget -O linpeas.sh https://github.com/carlospolop/PEASS-ng/releases/latest/download/linpeas.sh
chmod +x linpeas.sh

# Chkrootkit: Locally checks for signs of a rootkit
echo "[*] Downloading and compiling Chkrootkit..."
# Download chkrootkit securely over HTTPS from the official GitHub mirror
wget -O chkrootkit.tar.gz https://github.com/Magentron/chkrootkit/archive/master.tar.gz
# There is no official checksum provided in the repository, so we rely on HTTPS.
tar -xzf chkrootkit.tar.gz
(cd chkrootkit-*/ && make sense)
rm chkrootkit.tar.gz

# Rkhunter: Rootkit Hunter
echo "[*] Downloading Rkhunter..."
wget -O rkhunter.tar.gz https://sourceforge.net/projects/rkhunter/files/rkhunter/1.4.6/rkhunter-1.4.6.tar.gz/download
tar -xzf rkhunter.tar.gz
(cd rkhunter-* && ./installer.sh --layout default --install)
rm rkhunter.tar.gz

# Lynis: Security auditing tool for Unix derivatives
echo "[*] Cloning Lynis..."
git clone https://github.com/CISOfy/lynis.git

# ClamAV: Open source antivirus engine for detecting trojans, viruses, malware & other malicious threats.
echo "[*] Installing ClamAV..."
# This will use the package manager, as it's the most reliable way.
if command -v apt-get &> /dev/null; then
    apt-get update
    apt-get install -y clamav clamav-daemon
elif command -v yum &> /dev/null; then
    yum install -y clamav clamav-update
fi
# Update the virus database
freshclam

# witr: Why is this running? - Process investigation tool
echo "[*] Downloading witr..."
# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    WITR_ARCH="amd64"
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    WITR_ARCH="arm64"
else
    echo "[!] Unsupported architecture: $ARCH. Skipping witr download."
    WITR_ARCH=""
fi

if [ -n "$WITR_ARCH" ]; then
    wget -O witr https://github.com/pranshuparmar/witr/releases/latest/download/witr-linux-${WITR_ARCH}
    chmod +x witr
    echo "[+] witr downloaded successfully"
fi

# --- Finished ---
echo "[+] All tools have been downloaded to ${TOOLS_DIR}"
ls -l "${TOOLS_DIR}"
