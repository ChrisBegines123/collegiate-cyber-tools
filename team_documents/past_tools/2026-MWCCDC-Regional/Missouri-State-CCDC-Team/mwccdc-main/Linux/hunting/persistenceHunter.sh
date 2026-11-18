#!/bin/bash
# ==============================================================================
# Script Name : persistenceHunter.sh
# Description : hunt wabbits in the system, specifically persistence in linux.
# Author      : Tyler Olson
# Organization: Missouri State University
# Version     : 1.1
# ==============================================================================
# Changelog:
#   v1.0 - Creation! All basics are in here.
#   v1.1 - Fixed banner, Consolodated code.
# ==============================================================================

#!/bin/bash

echo -e "\n=== Linux Persistence Check ==="

# --- Cron Jobs ---
echo -e "\n--- Cron Jobs ---"
for user in $(cut -f1 -d: /etc/passwd); do
    crontab -l -u $user 2>/dev/null | sed "s/^/[$user] /"
done

# --- User Cron Spools ---
echo -e "\n--- User Cron Spools in /var/spool/cron/ ---"
ls -lh /var/spool/cron/ 2>/dev/null


echo -e "\n--- System Cron Directories ---"
for dir in /etc/cron.*; do
    echo -e "\n$dir"
    ls -lh $dir 2>/dev/null
done

# --- Systemd Services ---
echo -e "\n--- Systemd User Services ---"
for userhome in /home/*; do
    username=$(basename "$userhome")
    if [ -d "$userhome/.config/systemd/user" ]; then
        echo -e "\n[$username] ~/.config/systemd/user/"
        find "$userhome/.config/systemd/user" -name '*.service'
    fi
done

echo -e "\n--- Systemd System Services (Enabled) ---"
systemctl list-unit-files --state=enabled | grep '\.service'

# --- init.d Scripts ---
echo -e "\n--- init.d Scripts ---"
/bin/ls -lh /etc/init.d/ 2>/dev/null

# --- rc.local ---
echo -e "\n--- rc.local ---"
if [ -f /etc/rc.local ]; then
    cat /etc/rc.local
else
    echo "No rc.local file found."
fi

# --- Bash Profiles and Autostarts ---
echo -e "\n--- .bashrc / .profile / .bash_profile ---"
for home in /home/*; do
    user=$(basename "$home")
    for file in .bashrc .profile .bash_profile; do
        if [ -f "$home/$file" ]; then
            echo -e "\n[$user] $file"
            grep -Ev '^#|^$' "$home/$file"
        fi
    done
done

# --- System-wide Profile Scripts ---
echo -e "\n--- /etc/profile and /etc/profile.d/ ---"
grep -Ev '^#|^$' /etc/profile 2>/dev/null
ls -lh /etc/profile.d/ 2>/dev/null

# --- PAM Configuration ---
echo -e "\n--- PAM Configuration ---"
grep -r 'pam_exec' /etc/pam.d/ 2>/dev/null

# --- XDG Autostart ---
echo -e "\n--- XDG Autostart Entries ---"
for home in /home/*; do
    user=$(basename "$home")
    if [ -d "$home/.config/autostart" ]; then
        echo -e "\n[$user] ~/.config/autostart/"
        ls -lh "$home/.config/autostart"
        grep -H '^Exec=' "$home/.config/autostart/"*.desktop 2>/dev/null
    fi
done

# --- At Jobs ---
echo -e "\n--- at Jobs ---"
atq 2>/dev/null || echo "at daemon not active or no jobs"

# --- Upstart Jobs ---
echo -e "\n--- Upstart Jobs (/etc/init/*.conf) ---"
ls -lh /etc/init/*.conf 2>/dev/null

# --- LD_PRELOAD Entries ---
echo -e "\n--- LD_PRELOAD Entries ---"
for home in /home/*; do
    user=$(basename "$home")
    for file in .bashrc .profile .bash_profile; do
        if [ -f "$home/$file" ]; then
            grep 'LD_PRELOAD' "$home/$file" && echo "[$user] $file"
        fi
    done
done

echo -e "--- Current User's LD_PRELOAD ---"
echo $LD_PRELOAD

echo -e "\n=== End of Check ==="
