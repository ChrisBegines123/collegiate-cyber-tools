#!/usr/bin/env bash
# CyberPatriot Scripts - Scripts and checklists for use in CyberPatriot.
# Copyright (C) 2022  Adam Thompson-Sharpe
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, version 3.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

function get_users {
    # The <65534 condition is to skip the nobody user
    users=$(awk -F: '{if ($3 >= 1000 && $3 < 65534) print $1}' < /etc/passwd)
}

# prompt and reprompt_var functions from https://gitlab.com/-/snippets/2434448
function prompt {
    if [ "$2" = 'y' ]; then
        prompt_text="$1 [Y/n]: "
    elif [ "$2" = 'n' ]; then
        prompt_text="$1 [y/N]: "
    else
        prompt_text="$1 [y/n]: "
    fi

    while true; do
        read -r -p "$prompt_text" input

        case "$input" in
            [yY][eE][sS]|[yY])
                return 1
                ;;
            [nN][oO]|[nN])
                return 0
                ;;
            "")
                if [ "$2" = "y" ]; then return 1
                elif [ "$2" = "n" ]; then return 0
                else echo "Invalid response"
                fi
                ;;
            *)
                echo "Invalid response"
                ;;
        esac
    done
}

function reprompt_var {
    local reprompt_text="$1"
    local reprompt_new_val=''
    reprompt_value="${!2}"

    if [ $reprompt_value ]; then reprompt_text+=" [$reprompt_value]: "
    else reprompt_text+=': '; fi

    read -r -p "$reprompt_text" reprompt_new_val

    if [ "$reprompt_new_val" ]; then reprompt_value="$reprompt_new_val"; fi
}

# Update a config option in-place or append it to the file
# if not already defined
# Parameters are pattern to match, replace text, file to check
function sed_or_append {
    if grep -Eq "$1" "$3"; then
        sed -Ei "s\`$1\`$2\`g" "$3"
    else
        echo "$2" >> "$3"
    fi
}

echo '   ______      __'
echo '  / ____/_  __/ /_  ___  _____'
echo ' / /   / / / / __ \/ _ \/ ___/'
echo '/ /___/ /_/ / /_/ /  __/ /'
echo '\____/\__, /_.___/\___/_/'
echo '    _/____/     __       _       __'
echo '   / __ \____ _/ /______(_)___  / /_'
echo '  / /_/ / __ `/ __/ ___/ / __ \/ __/'
echo ' / ____/ /_/ / /_/ /  / / /_/ / /_'
echo '/_/    \__,_/\__/_/  /_/\____/\__/'
echo
echo 'Ubuntu CyberPatriot Script'
echo
echo 'CyberPatriot Scripts  Copyright (C) 2022  Adam Thompson-Sharpe'
echo 'Licensed under the GNU General Public License, Version 3.0'
echo
echo 'Make sure to run this as root!'
echo "Current user: $(whoami)"

# Config file locations
sshd_conf='/etc/ssh/sshd_config'
lightdm_conf='/etc/lightdm/lightdm.conf'
apt_periodic_conf='/etc/apt/apt.conf.d/10periodic'
apt_autoupgrade_conf='/etc/apt/apt.conf.d/20auto-upgrades'

# Permissive file search parameters
high_perm_min='700'
high_perm_file='high-perms.log'
high_perm_root='/'

sudo_group='sudo'

bad_software='aircrack-ng deluge gameconqueror hashcat hydra john nmap openvpn qbittorrent telnet wireguard zenmap'

# Password expiry settings
pass_max='90'
pass_min='7'
pass_warn='7'

# clamav settings
clamscan_path='/'
clamscan_logs='clamav.log'

found_media_file='media.log'

# Media file extensions
# Mostly from various Wikipedia pages' tables of extensions
# There are probably far more extensions than really necessary here,
# might be worth going through by hand at some point to see what can be removed
media_files_raw=(
    # Audio formats
    'aa'
    'aac'
    'aax'
    'act'
    'aif'
    'aiff'
    'alac'
    'amr'
    'ape'
    'au'
    'awb'
    'dss'
    'dvf'
    'flac'
    'gsm'
    'iklax'
    'ivs'
    'm4a'
    'm4b'
    'mmf'
    'mp3'
    'mpc'
    'msv'
    'nmf'
    'ogg'
    'oga'
    'mogg'
    'opus'
    'ra'
    'raw'
    'rf64'
    'sln'
    'tta'
    'voc'
    'vox'
    'wav'
    'wma'
    'wv'
    '8svx'
    'cda'
    # Video formats
    'webm'
    'mkv'
    'flv'
    'vob'
    'ogv'
    'ogg'
    'drc'
    'gif'
    'gifv'
    'mng'
    'avi'
    'mts'
    'm2ts'
    'mov'
    'qt'
    'wmv'
    'yuv'
    'rm'
    'rmvb'
    'viv'
    'asf'
    'amv'
    'mp4'
    'm4p'
    'm4v'
    'mpg'
    'mp2'
    'mpeg'
    'mpe'
    'mpv'
    'm2v'
    'svi'
    '3gp'
    '3g2'
    'mxf'
    'roq'
    'nsv'
    'f4v'
    'f4p'
    'f4a'
    'f4b'
    # Picture formats
    'png'
    'jpg'
    'jpeg'
    'jfif'
    'exif'
    'tif'
    'tiff'
    'gif'
    'bmp'
    'ppm'
    'pgm'
    'pbm'
    'pnm'
    'webp'
    'heif'
    'avif'
    'ico'
    'tga'
    'psd'
    'xcf'
)

found_media_file='media.log'
media_path='/'

media_files=()

# Convert list of extensions to parameters for find command
for extension in "${media_files_raw[@]}"; do
    if [ $media_files ]; then media_files+=('-o'); fi
    media_files+=('-iname')
    media_files+=("*.$extension")
done

### Regular expressions ###
# The caret (^) at the beginning of some expressions is to make sure that commented-out lines
# aren't accidentally matched instead of the actual config option

# Password expiry settings
pass_max_exp='^PASS_MAX_DAYS\s+[0-9]+'
pass_min_exp='^PASS_MIN_DAYS\s+[0-9]+'
pass_warn_exp='^PASS_WARN_AGE\s+[0-9]+'

# sshd settings
ssh_root_exp='^PermitRootLogin\s+(yes|no)'
ssh_empty_pass_exp='^PermitEmptyPasswords\s+(yes|no)'

# APT settings
apt_check_interval_exp='^APT::Periodic::Update-Package-Lists\s+"[0-9]+";'
apt_download_upgradeable_exp='^APT::Periodic::Download-Upgradeable-Packages\s+"[0-9]+";'
apt_autoclean_interval_exp='^APT::Periodic::AutocleanInterval\s+"[0-9]+";'
apt_unattended_exp='^APT::Periodic::Unattended-Upgrade\s+"[0-9]+";'

function menu {
    echo
    echo '01) Run updates                       10) Disable guest account'
    echo '02) Enable automatic updates          11) Set password expiry'
    echo '03) Enable & Configure UFW            12) Configure services'
    echo '04) Find/remove unauthorized users    13) Remove prohibited software'
    echo '05) Add missing users                 14) Clear /etc/rc.local'
    echo '06) Fix administrators                15) List files with high permissions'
    echo '07) Change all passwords              16) Run rkhunter'
    echo '08) Lock account                      17) Run clamav'
    echo '09) Add new group                     18) List media files'
    echo '                                      19) List services'
    echo
    echo '99) Exit script'
    read -r -p '> ' input

    case $(($input)) in
        # Run updates
        1)
            prompt 'Reboot after updates? Recommended if DE crashes during updates' 'n'
            reboot_after_update=$?
            apt-get update
            apt-get upgrade -y
            if [ $reboot_after_update = 1 ]; then reboot; fi
            echo 'Done updating!'
            ;;

        # Enable automatic updates
        2)
            sed_or_append "$apt_check_interval_exp" 'APT::Periodic::Update-Package-Lists "1";' "$apt_periodic_conf"
            echo 'Enabled daily update checks'

            sed_or_append "$apt_download_upgradeable_exp" 'APT::Periodic::Download-Upgradeable-Packages "1";' "$apt_periodic_conf"
            echo 'Enabled auto-downloading upgradeable packages'

            sed_or_append "$apt_autoclean_interval_exp" 'APT::Periodic::AutocleanInterval "7";' "$apt_periodic_conf"
            echo 'Enabled weekly autoclean'

            sed_or_append "$apt_unattended_exp" 'APT::Periodic::Unattended-Upgrade "1";' "$apt_periodic_conf"
            echo 'Enabled unattended upgrades'

            cp -f "$apt_periodic_conf" "$apt_autoupgrade_conf"

            echo 'Done configuring automatic updates!'
            ;;

        # Set up UFW
        3)
            apt-get install ufw -y

            rule='default deny'
            while ! [ "$rule" = '' ]; do
                ufw $rule
                read -r -p 'UFW rule to add, eg. `allow ssh` (leave blank to finish adding rules): ' rule
            done

            ufw enable
            echo 'Done configuring!'
            ;;

        # Find and remove unauthorized users
        4)
            reprompt_var 'Path to list of allowed usernames (normal users and admins)' users_file
            users_file="$reprompt_value"
            get_users

            unauthorized=()

            for user in $users; do
                if ! grep -Fxq "$user" "$users_file"; then
                    echo Unauthorized user: $user
                    unauthorized+=("$user")
                fi
            done

            if [ $unauthorized ]; then
                prompt 'Delete found users?'

                if [ $? = 1 ]; then
                    for user in "${unauthorized[@]}"; do
                        echo Deleting $user
                        userdel $user
                    done
                fi
            fi

            echo 'Done!'
            ;;

        # Add missing users
        5)
            reprompt_var 'Path to list of allowed usernames (normal users and admins)' users_file
            users_file="$reprompt_value"
            get_users

            while IFS= read -r user || [ -n "$user" ]; do
                if ! [ "$user" ]; then continue; fi
                if ! printf "$users" | grep -wq "$user"; then
                    echo Adding missing user $user
                    useradd $user
                fi
            done < "$users_file"

            echo 'Added missing users!'
            ;;

        # Fix administrators
        6)
            reprompt_var 'Path to list of administrators' admin_file
            admin_file="$reprompt_value"
            reprompt_var 'Path to list of normal users' normal_file
            normal_file="$reprompt_value"
            reprompt_var 'Name of sudoers group (generally `sudo` or `wheel`)' sudo_group
            sudo_group="$reprompt_value"
            get_users

            echo 'Ensuring admins are part of the sudo group'

            while IFS= read -r admin || [ -n "$admin" ]; do
                if ! [ "$admin" ]; then continue; fi
                if ! id -nG "$admin" | grep -qw "$sudo_group"; then
                    echo "User $admin doesn't have admin perms, fixing"
                    usermod -aG "$sudo_group" "$admin"
                fi
            done < "$admin_file"

            echo 'Ensuring standard users are not part of the sudo group'

            while IFS= read -r normal || [ -n "$normal" ]; do
                if ! [ "$normal" ]; then continue; fi
                if id -nG "$normal" | grep -qw "$sudo_group"; then
                    echo "User $normal has admin perms and shouldn't, fixing"
                    gpasswd --delete "$normal" "$sudo_group"
                fi
            done < "$normal_file"

            echo 'Done fixing administrators!'
            ;;

        # Change all passwords
        7)
	    get_users
            echo 'Changing passwords for the following users:'
	    echo $users
	    
            new_pass=''
            new_pass_confirm=''
            while ! [ "$new_pass" = "$new_pass_confirm" ] || [ "$new_pass" = '' ]; do
                read -s -p 'New password: ' new_pass
                echo
                read -s -p 'Confirm: ' new_pass_confirm
                echo

                if ! [ "$new_pass" = "$new_pass_confirm" ]; then echo 'Passwords do not match!'
                else
                    for user in $users; do
                        echo "Changing for $user..."
                        printf "$user:$new_pass" | chpasswd
                    done
                fi
            done

            echo 'Done changing passwords!'
            ;;

        # Lock account
        8)
            read -r -p 'Account to lock [root]: ' lock_account
            if [ "$lock_account" = '' ]; then lock_account='root'; fi
            usermod -L $lock_account
            echo "Locked $lock_account!"
            ;;

        # Add group
        9)
            read -r -p 'New group to add: ' new_group
            groupadd $new_group
            
            prompt 'Add members to this group?' 'y'
            if [ $? = 1 ]; then
                read -r -p 'Users to add (space-separated): ' new_group_users

                for user in $new_group_users; do
                    usermod -aG "$new_group" "$user"
                    echo "Added $user to $new_group"
                done
            fi

            echo 'Done creating new group!'
            ;;

        # Disable guest
        10)
            if [ -f "$lightdm_conf" ]; then
                if grep -q 'allow-guest=false' "$lightdm_conf"; then
                    echo 'Guest account already disabled!'
                else
                    echo 'allow-guest=false' >> "$lightdm_conf"
                    echo 'Disabled guest account!'
                fi
            else
                echo "lightdm config file not found at $lightdm_conf, guest account probably doesn't exist"
            fi
            ;;

        # Set password expiry
        11)
            reprompt_var 'Max password age' pass_max
            pass_max="$reprompt_value"
            reprompt_var 'Minimum password age' pass_min
            pass_min="$reprompt_value"
            reprompt_var 'Days before password expiry warning' pass_warn
            pass_warn="$reprompt_value"

            # Replace current values with new ones if possible,
            # otherwise append to end of file
            sed_or_append "$pass_max_exp" "PASS_MAX_DAYS	$pass_max" '/etc/login.defs'
            echo 'Set max age'

            sed_or_append "$pass_min_exp" "PASS_MIN_DAYS	$pass_min" '/etc/login.defs'
            echo 'Set minimum age'

            sed_or_append "$pass_warn_exp" "PASS_WARN_AGE	$pass_warn" '/etc/login.defs'
            echo 'Set age warning'

            echo 'Done setting password expiry!'
            ;;

        # Configure services
        12)
            ### sshd service ###
            prompt 'Allow ssh on machine?'

            if [ $? = 1 ]; then
                apt-get install ssh -y

                echo 'Configuring UFW rules'
                ufw allow ssh

                prompt 'Prohibit root login?' 'y'
                if [ $? = 1 ]; then yes_no='no'; else yes_no='yes'; fi
                sed_or_append "$ssh_root_exp" "PermitRootLogin $yes_no" "$sshd_conf"

                prompt 'Prohibit empty passwords?' 'y'
                if [ $? = 1 ]; then yes_no='no'; else yes_no='yes'; fi
                sed_or_append "$ssh_empty_pass_exp" "PermitEmptyPasswords $yes_no" "$sshd_conf"

                echo 'Restarting service'
                systemctl enable ssh
                systemctl restart ssh
                echo 'Done configuring ssh!'
            else
                echo 'Stopping service'
                systemctl stop ssh
                systemctl disable ssh
                echo 'Uninstalling'
                apt-get purge openssh-server -y
                'Configuring UFW rules'
                ufw delete allow ssh
                echo 'ssh disabled and purged!'
            fi

            ### Samba service ###
            prompt 'Allow Samba on machine?'

            if [ $? = 1 ]; then
                apt-get install samba -y

                echo 'Configuring UFW rules'
                ufw allow samba

                prompt 'Add Samba share? (Only do to add a brand-new share)'

                if [ $? = 1 ]; then
                    # Config options
                    read -r -p 'Share path: ' samba_share
                    read -r -p 'Share label: ' samba_label
                    prompt 'Readonly share?' 'n'
                    if [ $? = 1 ]; then readonly_share='yes'; else readonly_share='no'; fi
                    prompt 'Browsable share?' 'y'
                    if [ $? = 1 ]; then browsable_share='yes'; else browsable_share='no'; fi
                    browsable_share=$?

                    echo "[$samba_label]" >> /etc/samba/smb.conf
                    echo "    comment = Generated by script" >> /etc/samba/smb.conf
                    echo "    path = $samba_share" >> /etc/samba/smb.conf
                    echo "    read only = $readonly_share" >> /etc/samba/smb.conf
                    echo "    browsable = $browsable_share" >> /etc/samba/smb.conf

                    echo 'Share configured'
                fi

                echo 'Restarting service'
                systemctl enable smbd
                systemctl restart smbd
                echo 'Done configuring Samba!'
            else
                echo 'Stopping service'
                systemctl stop smbd
                systemctl disable smbd
                echo 'Uninstalling'
                apt-get purge samba -y
                'Configuring UFW rules'
                ufw delete allow samba
                echo 'Samba disabled and purged!'
            fi

            ### FTP service ###
            prompt 'Allow FTP on machine?'

            if [ $? = 1 ]; then
                apt-get install vsftpd -y

                echo 'Confugring UFW rules'
                ufw allow ftp

                systemctl enable vsftpd
                systemctl restart vsftpd
                echo "FTP configuration isn't currently automatic. See /etc/vsftpd.conf for config options"
            else
                echo 'Stopping sevice'
                systemctl stop vsftpd
                systemctl disable vsftpd
                echo 'Uninstalling'
                apt-get purge ftpd vsftpd -y
                echo 'Configuring UFW rules'
                ufw delete allow ftp
                echo 'FTP disabled and purged!'
            fi
            ;;

        # Remove prohibited software
        13)
            # The lack of the -y flag here is deliberate to make sure the user actually checks what's being removed
            apt-get purge $bad_software

            echo 'Prohibited software uninstalled!'
            echo 'Make sure that nothing else suspicious-looking is still on the desktop or elsewhere'
            ;;

        # Clear /etc/rc.local
        14)
            echo 'exit 0' > /etc/rc.local
            echo 'Cleared /etc/rc.local'
            ;;

        # List files with high permissions
        15)
            reprompt_var 'Minimum permission' high_perm_min
            high_perm_min="$reprompt_value"
            reprompt_var 'File to save paths to' high_perm_file
            high_perm_file="$reprompt_value"
            reprompt_var 'Search root' high_perm_root
            high_perm_root="$reprompt_value"

            echo 'Searching...'
            find "$high_perm_root" -type f -perm "-$high_perm_min" > "$high_perm_file"
            echo "Found $(wc -l < "$high_perm_file") files with permissions 700 or higher in $high_perm_root!"
            ;;

        # Run rkhunter
        16)
            apt-get install rkhunter -y
            rkhunter --update
            rkhunter -c --sk
            echo 'Done running rkhunter!'
            ;;

        # Run clamav
        17)
            clamscan_params=()

            reprompt_var 'Path to scan' clamscan_path
            clamscan_path="$reprompt_value"

            prompt 'Recurse?' 'y'
            if [ $? = 1 ]; then
                clamscan_params+=('--recursive')
            fi

            prompt 'Save log file?' 'y'
            if [ $? = 1 ]; then
                reprompt_var 'Path to log file' clamscan_logs
                clamscan_logs="$reprompt_value"
                clamscan_params+=('--log')
                clamscan_params+=("$clamscan_logs")
            fi

            prompt 'Only print infected files to stdout?' 'y'
            if [ $? = 1 ]; then
                clamscan_params+=('--infected')
            fi

            prompt 'Verbose output?' 'y'
            if [ $? = 1 ]; then
                clamscan_params+=('--verbose')
            fi

            apt-get install clamav -y

            prompt 'Enable freshclam service? (Only needs to be done once)' 'n'
            if [ $? = 1 ]; then
                systemctl enable clamav-freshclam
                systemctl start clamav-freshclam
            fi

            clamscan "$clamscan_path" ${clamscan_params[@]}
            ;;

        # List media files
        18)
            reprompt_var 'Output file' found_media_file
            found_media_file="$reprompt_value"
            reprompt_var 'Path to search' media_path
            media_path="$reprompt_value"
            prompt "Print files as they're found?" 'n'

            if [ $? = 1 ]; then
                echo 'Searching...'
                find "$media_path" -type f \( "${media_files[@]}" \) | tee "$found_media_file"
            else
                echo 'Searching...'
                find "$media_path" -type f \( "${media_files[@]}" \) > "$found_media_file"
            fi

            echo "Found $(wc -l < "$found_media_file") media files!"
            ;;

        # List services
        19)
            prompt 'Only show active services?' 'y'
            if [ $? = 1 ]; then systemctl list-units --type=service --state=active
            else systemctl list-units --type=service; fi
            ;;

        # Exit
        99)
            echo 'Good luck and happy hacking!'
            exit 0
            ;;

        # Invalid option
        *)
            echo "Unknown option $input"
            ;;
    esac
}

while true; do menu; done