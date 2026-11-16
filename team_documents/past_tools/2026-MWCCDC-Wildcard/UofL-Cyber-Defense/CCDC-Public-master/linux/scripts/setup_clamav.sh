#!/usr/bin/env nix
#! nix shell nixpkgs#bash nixpkgs#clamav nixpkgs#chkrootkit nixpkgs#shadow nixpkgs#killall --command bash
# Author: Collin Dewey
# Description:
# Runs ClamAV & chkrootkit
# Usage:
# ./<Script_Name>

SCAN_DIRS=( "/bin" "/home" "/lib" "/lib64" "/opt" "/root" "/sbin" "/usr" "/var" "/snap/bin" )
ONACC_SCAN_DIRS=( "/home" "/root" )

. $(dirname "$0")/helper.sh; if [ -z ${PUBLIC_KEY+x} ]; then exit 1; fi
root_check
nix_shell_guard

create_group clamav
create_user clamav clamav

if [ ! -d /etc/clamav ]; then
    mkdir -p /etc/clamav/quarantine
    mkdir -p /etc/clamav/db
    chown -R clamav /etc/clamav
fi

if [ ! -f /etc/clamav/freshclam.conf ]; then # https://github.com/Cisco-Talos/clamav/raw/main/etc/freshclam.conf.sample
    echo "
DatabaseMirror database.clamav.net
DatabaseDirectory /etc/clamav/db
DatabaseOwner clamav
    " > /etc/clamav/freshclam.conf
    #web freshclam
fi
# Freshclam was being weird. Download manually I guess. Cisco's mirror is behind cloudflare, so M$ it is
echo "Downloading main.cvd"
download https://packages.microsoft.com/clamav/main.cvd /etc/clamav/db/main.cvd
echo "Downloading daily.cvd"
download https://packages.microsoft.com/clamav/daily.cvd /etc/clamav/db/daily.cvd
echo "Downloading bytecode.cvd"
download https://packages.microsoft.com/clamav/bytecode.cvd /etc/clamav/db/bytecode.cvd

if [ ! -f /etc/clamav/clamd.conf ]; then # https://github.com/Cisco-Talos/clamav/raw/main/etc/clamd.conf.sample
    echo "
VirusEvent wall -n \"Alert: %v located in %f\"; chmod -x %f; chown clamav %f; mv %f /etc/clamav/quarantine
LocalSocket /run/clamav/clamd.sock
DatabaseDirectory /etc/clamav/db
OnAccessExcludeUname clamav
LogFile /var/log/clamd.log
ExcludePath ^/etc/clamav/
OnAccessPrevention no
DetectPUA yes
LogSyslog yes
ExitOnOOM yes
LogTime yes
User root
    " > /etc/clamav/clamd.conf
    for DIR in "${ONACC_SCAN_DIRS[@]}"; do
        echo "OnAccessIncludePath $DIR" >> /etc/clamav/clamd.conf
    done
fi

# SystemD
if command -v systemctl >/dev/null 2>&1; then
    echo "SystemD detected"
    if [ ! -f /etc/systemd/system/clamav-daemon.service ]; then
        echo "
[Unit]
Description=Clam AntiVirus userspace daemon

[Service]
ExecStart=$(which clamd) --foreground=true
ExecReload=$(which killall) clamd
TimeoutStartSec=420

[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/clamav-daemon.service
        systemctl enable clamav-daemon.service # "enable --now" wasn't a thing on older versions of SystemD
        systemctl start clamav-daemon.service
    fi
    if [ ! -f /etc/systemd/system/clamav-clamonacc.service ]; then
    echo "
[Unit]
Description=ClamAV On-Access Scanner
Requires=clamav-daemon.service
After=clamav-daemon.service

[Service]
Type=simple
User=root
ExecStart=$(which clamonacc) -F
ExecReload=$(which killall) -9 clamonacc

[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/clamav-clamonacc.service
    systemctl enable clamav-clamonacc.service
    fi
    if [ ! -f /etc/systemd/system/clamav-scan.service ]; then
    echo "
[Unit]
Description=ClamAV Routine Scan

[Service]
Type=oneshot
User=root
ExecStart=$(which bash) /etc/clamav/scan.sh

" > /etc/systemd/system/clamav-scan.service
    fi
    if [ ! -f /etc/systemd/system/clamav-scan.timer ]; then
    echo "
[Unit]
Description=ClamAV Routine Scan Timer

[Timer]
OnCalendar=*-*-* *:00/30:00

[Install]
WantedBy=timers.target
" > /etc/systemd/system/clamav-scan.timer
    fi
    systemctl start clamav-scan.timer
else
    echo "SystemD not detected"
    echo "Executing clamd"
    killall clamd -qw # Kill existing
    clamd # Forks to background
fi

# Iterate over each directory and perform the scan
echo "#!$(which bash)" > /etc/clamav/scan.sh
chmod +x /etc/clamav/scan.sh

for DIR in "${SCAN_DIRS[@]}"; do
    if [ -d "$DIR" ]; then
        echo "echo -e \"\nScanning $DIR\" | tee -a /var/log/clamdscan.log" >> /etc/clamav/scan.sh
        echo "$(which clamdscan) \"$DIR\" --multiscan --infected --wait | tee -a /var/log/clamdscan.log" >> /etc/clamav/scan.sh
    fi
done

echo "Executing chkrootkit"
chkrootkit | tee /var/log/chkrootkit.log
echo "Executing clamdscan"
bash /etc/clamav/scan.sh

echo "Results in /var/log/chkrootkit.log"
echo "Results in /var/log/clamdscan.log"

echo "Starting clamonacc"
if command -v systemctl >/dev/null 2>&1; then
    systemctl start clamav-clamonacc.service
else
    killall clamonacc -9qw # Kill existing
    clamonacc # Forks to background
fi