#!/bin/bash

# To get this script to work, run "chmod +x ./Ubuntu22.sh"
# To find all apt apps installed, run "apt list --installed"
# Please run this script as root.
# Fun fact: The text editor app on ubuntu can be run from command line with "gedit"

# This is the main function.  It acts as a menu.
function main {
    printf "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n"
    printf "             __     __   _______    __     __   ___      __   ________   __     __        ______     ______             \n"
    printf "            /  |   /  | /       \  /  |   /  | /   \    /  | /        | /  |   /  |      /      \   /      \            \n"
    printf "            && |   && | &&&&&&&  \ && |   && | &&&& \   && | &&&&&&&&_/ && |   && |     /&&&&&&  | /&&&&&&  |           \n"
    printf "            && |   && | && |  && | && |   && | && && \  && |    && |    && |   && |     &&_/  && | &&_/  && |           \n"
    printf "            && |   && | && |  && / && |   && | && &&  \ && |    && |    && |   && |           && |       && |           \n"
    printf "            && |   && | &&&&&&& <  && |   && | && | && \&& |    && |    && |   && |          && /       && /            \n"
    printf "            && |   && | && |  && \ && |   && | && | &&  && |    && |    && |   && |        &&& /      &&& /             \n"
    printf "            && |   && | && |  && | && |   && | && |  && && |    && |    && |   && |      &&&  /___  &&&  /___           \n"
    printf "             &&&&&&&_/  &&&&&&&__/  &&&&&&&_/  &&_/   &&&&_/    &&_/     &&&&&&&_/      &&&&&&&&_/ &&&&&&&&_/           \n"
    printf "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Written by: Jackson Campbell ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n"
    printf "     0) Exit Program                                                                                                    \n"
    printf "     1) Reinstall APT                                                                                                   \n"
    printf "     2) Update APT and snap                                                                                             \n"
    printf "     3) Install tools and uninstall unnecessary apps                                                                    \n"
    printf "     4) Stop & disable unnecessary services                                                                             \n"
    printf "     5) Configure APT settings                                                                                          \n"
    printf "     6) Create users & groups                                                                                           \n"
    printf "     7) Add users to groups + Delete users & groups                                                                     \n"
    printf "     8) Change passwords for all to Somethingsecur3!                                                                    \n"
    printf "     9) Null passwords do not Auth                                                                                      \n"
    printf "    10) Set Admin Perms (Removes admin for all; Must enter all current admins!)                                         \n"
    printf "    11) Setup Auditd                                                                                                    \n"
    printf "    12) Run CHRootkit                                                                                                   \n"
    printf "    13) Run RKHunter                                                                                                    \n"
    printf "           - Programs such as ps, ss, and lsof can help when looking for malware.                                       \n"
    printf "           - Check the following: 'sudo ss -tlnp' and then 'sudo nano /etc/crontab'                                     \n"
    printf "           - Then 'sudo pkill -f <service_name>' and 'which <service_name>' and 'sudo rm /usr/bin/<service_name>'       \n"
    printf "    14) Config & Install Firewalld                                                                                      \n"
    printf "    15) Config & run UFW                                                                                                \n"
    printf "    16) Config Logwatch                                                                                                 \n"
    printf "    17) Config SSH                                                                                                      \n"
    printf "    18) Fix File Permissions                                                                                            \n"
    printf "    19) Configure Password Policy                                                                                       \n"
    printf "    20) Set Account Lockout Policy                                                                                      \n"
    printf "    21) Config Sysctl Security                                                                                          \n"
    printf "    22) Disable Guest Account                                                                                           \n"
    printf "    23) Config Sudo Policy                                                                                              \n"
    printf "    24) Secure FTP                                                                                                      \n"
    printf "    25) Set IP Spoofing Protection (Deprecated)                                                                         \n"
    printf "    26) Manage Ports                                                                                                    \n"
    printf "    27) List Prohibited Files (pics.txt, audio.txt, vids.txt)                                                           \n"
    printf "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n"

    read -r answer
    if [ "$answer" -eq 0 ]
        then exit;
    elif [ "$answer" -eq 1 ]
        then reinstall_apt;
    elif [ "$answer" -eq 2 ]
        then update_apps;
    elif [ "$answer" -eq 3 ]
        then manage_apps;
    elif [ "$answer" -eq 4 ]
        then stop_services;
    elif [ "$answer" -eq 5 ]
        then config_apt;
    elif [ "$answer" -eq 6 ]
        then create_users_groups;
    elif [ "$answer" -eq 7 ]
        then add_delete_users_groups;
    elif [ "$answer" -eq 8 ]
        then change_passwords;
    elif [ "$answer" -eq 9 ]
        then disable_null_passwords;
    elif [ "$answer" -eq 10 ]
        then set_admin_permissions;
    elif [ "$answer" -eq 11 ]
        then setup_auditd;
    elif [ "$answer" -eq 12 ]
        then config_chrootkit;
    elif [ "$answer" -eq 13 ]
        then config_rkhunter;
    elif [ "$answer" -eq 14 ]
        then config_firewalld;
    elif [ "$answer" -eq 15 ]
        then setup_ufw;
    elif [ "$answer" -eq 16 ]
        then config_logwatch;
    elif [ "$answer" -eq 17 ]
        then config_ssh;
    elif [ "$answer" -eq 18 ]
        then fix_file_permissions;
    elif [ "$answer" -eq 19 ]
        then config_password_policy;
    elif [ "$answer" -eq 20 ]
        then account_lockout_policy;
    elif [ "$answer" -eq 21 ]
        then config_sysctl_security;
    elif [ "$answer" -eq 22 ]
        then disable_guest_account;
    elif [ "$answer" -eq 23 ]
        then config_sudo_policy;
    elif [ "$answer" -eq 24 ]
        then secure_ftp;
    elif [ "$answer" -eq 25 ]
        then config_ip_spoofing_protection;
    elif [ "$answer" -eq 26 ]
        then manage_ports;
    elif [ "$answer" -eq 27 ]
        then list_prohibited_files;
    else
        main;
    fi
}

function reinstall_apt {
    # Ask user for specific APT version or reinstall the current apt version
    # Check http://us.archive.ubuntu.com/ubuntu/pool/main/a/apt/ for ubuntu/mint
    # Check https://ftp.debian.org/debian/pool/main/a/apt/ for debian
    echo "Please enter the APT version you'd like to install to the system.  The version needs to be available in the operating system's repositories.  To auto-detect the version based on the installed version, enter nothing."
    echo "This DOES NOT WORK for every APT version."
    read -r APT_VERS

    # Checking if the APT_VERS variable is empty
    if [ "$APT_VERS" = "" ]; then
        # Detecting the installed apt version
        APT_VERS=$(apt -v | awk '{print $2}')
    fi

    echo "Installing APT version ${APT_VERS}"
    
    # Getting the OS and codename from /etc/os-release
    OS=$(awk -F= '{if ($1 == "ID") print $2}' < /etc/os-release)
    CODENAME=$(awk -F= '{if ($1 == "VERSION_CODENAME") print $2}' < /etc/os-release)

    if [ "$OS" = "debian" ]; then
        # Installing apt
        reinstall_apt_install_apt "http://deb.debian.org/debian/pool/main/a/apt" $APT_VERS

        # Configure Debian repositories
        echo "deb http://deb.debian.org/debian ${CODENAME} contrib main non-free non-free-firmware" # | sudo tee /etc/apt/sources.list
        echo "deb http://ftp.debian.org/debian ${CODENAME}-backports contrib main non-free non-free-firmware" # | sudo tee -a /etc/apt/sources.list
        echo "deb http://deb.debian.org/debian ${CODENAME}-updates contrib main non-free non-free-firmware" # | sudo tee -a /etc/apt/sources.list
        echo "deb http://security.debian.org/debian-security ${CODENAME}-security contrib main non-free non-free-firmware updates" # | sudo tee -a /etc/apt/sources.list
    elif [ "$OS" = "ubuntu" ]; then
        # Installing apt
        reinstall_apt_install_apt "http://us.archive.ubuntu.com/ubuntu/pool/main/a/apt" $APT_VERS

        # Configure Ubuntu repositories
        echo "deb http://archive.ubuntu.com/ubuntu ${CODENAME} main multiverse restricted universe" # | sudo tee /etc/apt/sources.list
        echo "deb http://archive.ubuntu.com/ubuntu ${CODENAME}-backports main multiverse restricted universe" # | sudo tee -a /etc/apt/sources.list
        echo "deb http://archive.ubuntu.com/ubuntu ${CODENAME}-security main multiverse restricted universe" # | sudo tee -a /etc/apt/sources.list
        echo "deb http://archive.ubuntu.com/ubuntu ${CODENAME}-updates main multiverse restricted universe" # | sudo tee -a /etc/apt/sources.list
    elif [ "$OS" = "linuxmint" ]; then
        # Installing apt
        reinstall_apt_install_apt "http://us.archive.ubuntu.com/ubuntu/pool/main/a/apt" $APT_VERS

        # Get the Ubuntu base version
        UBUNTU_BASE=$(grep UBUNTU_CODENAME /etc/os-release | cut -d= -f2)

        # Configure Linux Mint repositories
        echo "deb http://packages.linuxmint.com ${CODENAME} main upstream import backport #id:linuxmint_main" # | sudo tee /etc/apt/sources.list.d/official-package-repositories.list
        echo "deb http://archive.ubuntu.com/ubuntu ${UBUNTU_BASE} main restricted universe multiverse" # | sudo tee -a /etc/apt/sources.list.d/official-package-repositories.list
        echo "deb http://archive.ubuntu.com/ubuntu ${UBUNTU_BASE}-updates main restricted universe multiverse" # | sudo tee -a /etc/apt/sources.list.d/official-package-repositories.list
        echo "deb http://archive.ubuntu.com/ubuntu ${UBUNTU_BASE}-backports main restricted universe multiverse" # | sudo tee -a /etc/apt/sources.list.d/official-package-repositories.list
        echo "deb http://security.ubuntu.com/ubuntu ${UBUNTU_BASE}-security main restricted universe multiverse" # | sudo tee -a /etc/apt/sources.list.d/official-package-repositories.list
    else
        echo "Unrecognized OS.  This function is only built for debian, ubuntu, and linux mint"
    fi
    
    read -rp "Press [Enter] to return to the menu."
    main
}

# Helper function for reinstall_apt that installs APT based on two parameters
function reinstall_apt_install_apt {
    # Validating parameters
    if [ "${1}" = "" ]; then
        echo "ERROR: url parameter was not provided.  Please specify the url for the apt package for your distro"
        return
    elif [ "${2}" = "" ]; then
        echo "ERROR: apt version parameter was not provided.  Please specify the version of apt to install"
        return
    fi
    
    # Downloading apt debs
    mkdir aptinstall

    APT_FILES=$(curl https://deb.debian.org/debian/pool/main/a/apt/ | grep "${2}_amd64.deb" | awk -F\> '{ print $7 }' | sed '/libapt-pkg-dev/d' | sed -r 's/<\/a//')
    for f in $APT_FILES; do
        echo "Downloading \"${1}/${f}\" to aptinstall/${f}"
        wget "${1}/${f}" -O aptinstall/
    done

    # Installing apt
    echo "Installing apt"
    dpkg -Ri ./aptinstall

    # Cleaning up files
    echo "Deleting installation files"
    rm -rf ./aptinstall
}

# This function updates apps from the snap store and apps from apt.
function update_apps {
    sudo snap refresh
    sudo apt update
    sudo apt upgrade -y
    sudo apt --fix-broken install -y
    sudo apt autoremove -y
    
    read -rp "Press [Enter] to return to the menu."
    main
}

function manage_apps {
    # Updating again to make sure everything is up to date (Can't be too careful!)
    update_apps

    # Uninstalling prohibited apps
    # Hacking tools
    sudo apt remove -y \
    aircrack-ng apktool  autopsy \
    deluge      dirb     dsniff  \
    ettercap    ftp     \
    gobuster    hashcat  httrack \
    hydra       john     medusa  \
    minetest    nbtscan  ncrack  \
    netcat      nikto    nmap    \
    ophcrack    rfdump   smbmap  \
    snort       sqlmap   tshark  \
    vuze        wfuzz    wifite  \
    wireshark   yersinia zenmap  \
    zmap

    # Games
    sudo apt remove -y \
    aisleriot   endless-sky   freeciv         \
    goldeneye   gameconqueror gnome-mahjongg  \
    gnome-mines gnome-sudoku  wesnoth

    # Insecure software
    sudo apt remove -y \
    manaplus   nis        rpcbind \
    rsh-client rsh-server rsync   \
    talk       telnet     telnetd

    # Other
    sudo apt remove -y \
    amule           apport         autofs \
    avahi-daemon    avahi-utils    bind9 \
    cups            doona          dovecot-imapd \
    dovecot-pop3d   fcrackzip      iptables-persistent \
    isc-dhcp-server nfs-common     nfs-kernel-server \
    nginx           packit         pompem \
    portmap         proxychains    rhythmbox-plugin-zeitgeist \
    rpcbind         slapd          squidclient \
    squid-cgi       themole        xprobe \
    zeitgeist       zeitgeist-core zeitgeist-datahub \
    nmapsi4         pumpa          zangband
    
    read -rp "Press [Enter] to return to the menu."
    main
}

function stop_services {
    local services_to_disable=(
        # Web servers
        "apache2" "nginx" "lighttpd" "tomcat" "httpd"
        
        # Database servers
        "mysql" "postgresql" "mongodb" "redis-server" "cassandra"
        
        # File sharing
        "vsftpd" "proftpd" "pure-ftpd" "nfs" "smbd" "nmbd" "samba"
        
        # Remote access
        "vncserver" "xrdp" "telnet" "telnetd" "rsh" "rsh-server" "rlogin" "vino" "rexec"
        
        # DNS/DHCP
        "bind9" "named" "dhcpd" "dnsmasq"
        
        # Mail servers
        "postfix" "sendmail" "exim4" "dovecot"
        
        # Game servers
        "openarena-server" "minecraft-server"
        
        # Chat/IRC
        "ircd" "inspircd" "unrealircd"
        
        # Legacy/Insecure
        "inetd" "xinetd" "rpcbind" "nis"
        
        # Proxy/Cache
        "squid" "privoxy" "polipo"
        
        # Print servers
        "cups" "cupsd"
        
        # Time servers
        "ntp" "chronyd"
        
        # Misc network services
        "rsyncd" "tftp" "snmpd" "avahi-daemon"
    )
    
        for service_name in "${services_to_disable[@]}"; do
            if systemctl list-unit-files | grep -q "$service_name"; then
                echo "Stopping and disabling $service_name..."
                systemctl stop "$service_name" 2>/dev/null
                systemctl disable "$service_name" 2>/dev/null
            fi
        done
        echo "Prohibited services have been stopped and disabled."
        read -rp "Press [Enter] to return to the menu."
        main
}

function config_apt {
    # Making installs require secure ssl connection
    apt-get install -y wget ca-certificates
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
    echo "deb http://apt.postgresql.org/pub/repos/apt/ $CODENAME-pgdg main" | sudo tee -a /etc/apt/sources.list.d/pgdg.list

    # Configuring
    echo "APT::Periodic::Update-Package-Lists \"1\";" | sudo tee -a /etc/apt/apt.conf.d/10periodic
    echo "APT::Periodic::Download-Upgradeable-Packages \"1\";" | sudo tee -a /etc/apt/apt.conf.d/10periodic
    echo "APT::Periodic::AutocleanInterval \"7\";" | sudo tee -a /etc/apt/apt.conf.d/10periodic
    echo "APT::Periodic::Unattended-Upgrade \"1\";" | sudo tee -a /etc/apt/apt.conf.d/10periodic
    
    read -rp "Press [Enter] to return to the menu."
    main
}

function create_users_groups {
    # This creates users
    while true
    do
        echo "Enter the name of a user to add.  Type '0' to move on."
        read -r user
        if [ "$user" -eq 0 ]
            then break
        else
            useradd "$user" -m
        fi
    done

    # This creates groups
    while true
    do
        echo "Enter the name of a group to add.  Type '0' to move on."
        read -r group
        if [ "$group" -eq 0 ]
            then break
        else
            groupadd "$group" -m
        fi
    done

    read -rp "Press [Enter] to return to the menu."
    main
}

function add_delete_users_groups {
    # This adds users to existing groups
    while true
    do
        echo "Enter a group to add to.  Type '0' to move on."
        read -r group
        if [ "$group" -eq 0 ]
            then break
        else
            echo "Now enter a user to add to $group"
            read -r user
            usermod -aG "$group" "$user"
        fi
    done

    # This deletes users
    while true
    do
        echo "Enter the name of a user to delete.  Type '0' to move on."
        read -r user
        if [ "$user" -eq 0 ]
            then break
        else
            userdel "$user"
        fi
    done

    # This deletes groups
    while true
    do
        echo "Enter the name of a group to delete.  Type '0' to move on."
        read -r group
        if [ "$group" -eq 0 ]
            then break
        else
            groupdel "$group"
        fi
    done

    read -rp "Press [Enter] to return to the menu."
    main
}

function change_passwords {
    # These commands will change the passwords of every user
    echo "Setting all passwords to Somethingsecur3!"
    for user in $(getent passwd | awk -F: '{if ($3 > 999) print $1}')
    do
        echo "$user:Somethingsecur3!" | sudo chpasswd
    done
    
    read -rp "Press [Enter] to return to the menu."
    main
}

function disable_null_passwords {
    # Backup original file
    sudo cp /etc/pam.d/common-auth /etc/pam.d/common-auth.bak

    # Also remove 'nullok_secure' if it exists
    sudo sed -i 's/\(pam_unix.so\s\+nullok_secure\)/pam_unix.so/' /etc/pam.d/common-auth
    
    # Remove 'nullok' from pam_unix.so line
    sudo sed -i 's/\(pam_unix.so\s\+nullok\)/pam_unix.so/' /etc/pam.d/common-auth
    
    if grep -q "nullok" /etc/pam.d/common-auth; then
        echo "Failed to remove nullok"
        read -rp "Press [Enter] to return to the menu."
    	main
        return 1
    else
        echo "Disabled nullok"
        read -rp "Press [Enter] to return to the menu."
    	main
    	return 0
    fi

    read -rp "Press [Enter] to return to the menu."
    main
}

function set_admin_permissions {
    # These commands will remove admin rights from all users and then give them back
    # Removing admin permissions from all users with a UID > 999 and not equal to 65534 or the current user's id

    for user in $(getent passwd | awk -F: -v USER_ID=$(id -u) '{if ($3 > 999 && $3 != 65534 && $3 != USER_ID) print $1}')
    do
        usermod -G "$user" "$user"
    done

    # Giving back admin permissions
    while true
    do
        echo "Enter the name of ALL authorized admins one by one.  Type '0' to move on."
        read -r admin
        if [ "$admin" -eq 0 ]
            then break
        else
            usermod -aG "sudo" "$admin"
        fi
    done

    echo "Check the files in this directory to find more vulnerabilities."
    echo "Manage Software Updater (Things like installing important security updates and automatically checking for updates daily)"

    read -rp "Press [Enter] to return to the menu."
    main
}

function setup_auditd {
    # Setting up auditd
    systemctl --now enable auditd
    augenrules --load
    echo "max_log_file_action = keep_logs" | sudo tee -a /etc/audit/auditd.conf

    # Time Rules
    echo "-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change" | sudo tee -a /etc/audit/rules.d/time.rules
    echo "-a always,exit -F arch=b32 -S adjtimex -S settimeofday -k time-change" | sudo tee -a /etc/audit/rules.d/time.rules
    echo "-a always,exit -F arch=b32 -S clock_settime -k time-change" | sudo tee -a /etc/audit/rules.d/time.rules
    echo "-a always,exit -F arch=b64 -S clock_settime -k time-change" | sudo tee -a /etc/audit/rules.d/time.rules
    echo "wa -k time-change" | sudo tee -a /etc/audit/rules.d/time.rules

    # System Locale Rules
    echo "-a always,exit -F arch=b64 -S sethostname -S setdomainname -k system-locale" | sudo tee -a /etc/audit/rules.d/system-locale.rules
    echo "-a always,exit -F arch=b32 -S sethostname -S setdomainname -k system-locale" | sudo tee -a /etc/audit/rules.d/system-locale.rules
    echo "-w /etc/issue -p wa -k system-locale" | sudo tee -a /etc/audit/rules.d/system-locale.rules
    echo "-w /etc/issue.net -p wa -k system-locale" | sudo tee -a /etc/audit/rules.d/system-locale.rules
    echo "-w /etc/hosts -p wa -k system-locale" | sudo tee -a /etc/audit/rules.d/system-locale.rules
    echo "-w /etc/network -p wa -k system-locale" | sudo tee -a /etc/audit/rules.d/system-locale.rules

    # Identity Rules
    echo "-w /etc/group -p wa -k identity" | sudo tee -a /etc/audit/rules.d/identity.rules
    echo "-w /etc/passwd -p wa -k identity" | sudo tee -a /etc/audit/rules.d/identity.rules
    echo "-w /etc/gshadow -p wa -k identity" | sudo tee -a /etc/audit/rules.d/identity.rules
    echo "-w /etc/shadow -p wa -k identity" | sudo tee -a /etc/audit/rules.d/identity.rules
    echo "-w /etc/security/opasswd -p wa -k identity" | sudo tee -a /etc/audit/rules.d/identity.rules

    # Login Rules
    echo "-w /var/log/faillog -p wa -k logins" | sudo tee -a /etc/audit/rules.d/logins.rules
    echo "-w /var/log/lastlog -p wa -k logins" | sudo tee -a /etc/audit/rules.d/logins.rules
    echo "-w /var/log/tallylog -p wa -k logins" | sudo tee -a /etc/audit/rules.d/logins.rules

    # Permissions Rules
    echo "-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod" | sudo tee -a /etc/audit/rules.d/permissions.rules
    echo "-a always,exit -F arch=b32 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod" | sudo tee -a /etc/audit/rules.d/permissions.rules
    echo "-a always,exit -F arch=b64 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod" | sudo tee -a /etc/audit/rules.d/permissions.rules
    echo "-a always,exit -F arch=b32 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod" | sudo tee -a /etc/audit/rules.d/permissions.rules
    echo "-a always,exit -F arch=b64 -S setxattr -S lsetxattr -S fsetxattr -S removexattr -S lremovexattr -S fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm_mod" | sudo tee -a /etc/audit/rules.d/permissions.rules
    echo "-a always,exit -F arch=b32 -S setxattr -S lsetxattr -S fsetxattr -S removexattr -S lremovexattr -S fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm_mod" | sudo tee -a /etc/audit/rules.d/permissions.rules

    # File Change Rules
    echo "-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete" | sudo tee -a /etc/audit/rules.d/file-change.rules
    echo "-a always,exit -F arch=b32 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete" | sudo tee -a /etc/audit/rules.d/file-change.rules

    # Scope Rules
    echo "-w /etc/sudoers -p wa -k scope" | sudo tee -a /etc/audit/rules.d/scope.rules
    echo "-w /etc/sudoers.d/ -p wa -k scope" | sudo tee -a /etc/audit/rules.d/scope.rules

    # Rules
    echo "-a always,exit -F arch=b64 -C euid!=uid -F euid=0 -Fauid>=1000 -F auid!=4294967295 -S execve -k actions" | sudo tee -a /etc/audit/rules.d/sudo.rules
    echo "-a always,exit -F arch=b32 -C euid!=uid -F euid=0 -Fauid>=1000 -F auid!=4294967295 -S execve -k actions" | sudo tee -a /etc/audit/rules.d/sudo.rules

    # Module Rules
    echo "-w /sbin/insmod -p x -k modules" | sudo tee -a /etc/audit/rules.d/modules.rules
    echo "-w /sbin/rmmod -p x -k modules" | sudo tee -a /etc/audit/rules.d/modules.rules
    echo "-w /sbin/modprobe -p x -k modules" | sudo tee -a /etc/audit/rules.d/modules.rules
    echo "-a always,exit -F arch=b64 -S init_module -S delete_module -k modules" | sudo tee -a /etc/audit/rules.d/modules.rules

    # Reloading audit config
    auditctl -e 1 /etc/audit/rules.d/time.rules
    auditctl -e 1 /etc/audit/rules.d/system-locale.rules
    auditctl -e 1 /etc/audit/rules.d/identity.rules
    auditctl -e 1 /etc/audit/rules.d/logins.rules
    auditctl -e 1 /etc/audit/rules.d/permissions.rules
    auditctl -e 1 /etc/audit/rules.d/file-change.rules
    auditctl -e 1 /etc/audit/rules.d/scope.rules
    auditctl -e 1 /etc/audit/rules.d/sudo.rules
    auditctl -e 1 /etc/audit/rules.d/modules.rules

    # Reloading auditd
    systemctl restart auditd
    augenrules --load

    read -rp "Press [Enter] to return to the menu."
    main
}

function config_chrootkit {
    # Get the actual user's home directory
    REAL_USER=$(who am i | awk '{print $1}')
    USER_HOME=$(eval echo ~${REAL_USER})
    
    # First check if chkrootkit is installed, if not install it
    if ! command -v chkrootkit &> /dev/null; then
        sudo apt-get update
        sudo apt-get install chkrootkit -y
    fi

    # Running chkrootkit and saving output
    echo "Chkrootkit scan run on $(date)" > "${USER_HOME}/Desktop/RootKitInfo.txt"
    sudo chkrootkit >> "${USER_HOME}/Desktop/RootKitInfo.txt" 2>&1

    # Making chkrootkit run daily
    echo 'RUN_DAILY="true"' | sudo tee -a /etc/chkrootkit.conf

    echo "Scan complete. Results saved to ${USER_HOME}/Desktop/RootKitInfo.txt"
    read -rp "Press [Enter] to return to the menu."
    main
}

function config_rkhunter {
    # Check if rkhunter is installed
    if ! command -v rkhunter &> /dev/null; then
        echo "rkhunter is not installed. Install? (y/n)"
        read -r install_rkhunter
        if [[ "$install_rkhunter" == "y" || "$install_rkhunter" == "Y" ]]; then
            if command -v yum &> /dev/null; then
                sudo yum install -y rkhunter
            elif command -v apt-get &> /dev/null; then
                sudo apt-get install -y rkhunter
            else
                echo "Install rkhunter manually"
                read -rp "Press [Enter] to return to the menu."
                main
            fi
        else
            echo "rkhunter installation skipped."
            read -rp "Press [Enter] to return to the menu."
            main
        fi
    fi

    # Editing rkhunter configuration
    sudo tee -a /etc/rkhunter.conf > /dev/null << EOF
UPDATE_MIRRORS=1
CRON_DAILY_RUN=true
ALLOW_SSH_ROOT_USER=no
ALLOW_SSH_PROT_1=no
ALLOW_SYSLOG_REMOTE=no
USER_SYSLOG=authpriv.notice
WEB_CMD=/usr/bin/wget
EOF

    # Enforce sudo authentication
    echo "Defaults authenticate" | sudo tee -a /etc/sudoers

    # Update and initialize rkhunter
    sudo rkhunter --update
    sudo rkhunter --propupd  # Create initial hash database

    # Run rkhunter scan
    echo "Running rkhunter scan..."
    sudo rkhunter --check --skip-keypress

    # Note: Daily scans are configured via CRON_DAILY_RUN=true in config file
    
    read -rp "Press [Enter] to return to the menu."
    main
}

function config_firewalld {
    # Check if firewalld is installed
    if ! command -v firewall-cmd &> /dev/null; then
        echo "firewalld isn't installed. Install? (y/n)"
        read -r install_firewalld
        if [[ "$install_firewalld" == "y" ]]; then
            if command -v yum &> /dev/null; then
                sudo yum install -y firewalld
            elif command -v apt-get &> /dev/null; then
                sudo apt-get install -y firewalld
            else
                echo "Install firewalld manually"
                return
            fi
        else
            echo "firewalld installation skipped."
            read -rp "Press [Enter] to return to the menu."
    	    main
        fi
    fi

    # Enable and start firewalld
    systemctl enable firewalld
    systemctl start firewalld

    # Set default zone to drop
    firewall-cmd --set-default-zone=drop

    # Check if SSH service is available before allowing it
    if systemctl is-active --quiet sshd; then
        firewall-cmd --permanent --add-service=ssh
    else
        echo "SSH service not active. Skipping SSH config"
    fi

    # Allow essential services
    firewall-cmd --permanent --add-service=https
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=dns

    # Block common attack vectors
    firewall-cmd --permanent --add-icmp-block=echo-request
    firewall-cmd --permanent --add-icmp-block=echo-reply

    # Rate limiting for SSH connection attempts, if SSH is enabled
    if systemctl is-active --quiet sshd; then
        firewall-cmd --permanent --add-rich-rule='rule service name=ssh limit value=3/m accept'
    fi

    # Block common malicious ports
    firewall-cmd --permanent --add-port=21/tcp --remove-port=21/tcp
    firewall-cmd --permanent --add-port=23/tcp --remove-port=23/tcp
    firewall-cmd --permanent --add-port=2049/tcp --remove-port=2049/tcp
    firewall-cmd --permanent --add-port=515/tcp --remove-port=515/tcp

    firewall-cmd --reload

    read -rp "Press [Enter] to return to the menu."
    main
}

function setup_ufw {
    if ! command -v ufw &> /dev/null; then
        echo "UFW is not installed"
        return 1
    fi

    ufw --force reset

    ufw default deny incoming
    ufw default allow outgoing
    
    ufw allow in on lo
    ufw allow out on lo
    ufw deny in from 127.0.0.0/8
    ufw deny in from ::1

    ufw allow ssh
    ufw allow http
    
    ufw deny telnet
    ufw deny 2049
    ufw deny icmp
    
    ufw --force enable
    
    ufw status verbose

    read -rp "Press [Enter] to return to the menu."
    main
}

function config_logwatch {
    # Check if logwatch is installed
    if ! command -v logwatch >/dev/null 2>&1; then
        echo "Error: Please install logwatch first"
        read -rp "Press [Enter] to return to the menu."
        return 1
    }

    sudo mkdir -p /var/cache/logwatch /etc/logwatch/conf/
    
    sudo cp /usr/share/logwatch/default.conf/logwatch.conf /etc/logwatch/conf/
    echo "Output = mail"                          | sudo tee -a /etc/logwatch/conf/logwatch.conf
    echo "MailTo = me@mydomain.org"               | sudo tee -a /etc/logwatch/conf/logwatch.conf
    echo "MailFrom = logwatch@host1.mydomain.org" | sudo tee -a /etc/logwatch/conf/logwatch.conf
    echo "Detail = Low"                           | sudo tee -a /etc/logwatch/conf/logwatch.conf
    echo "Service = All"                          | sudo tee -a /etc/logwatch/conf/logwatch.conf
    echo "Service = '-http'"                      | sudo tee -a /etc/logwatch/conf/logwatch.conf
    echo "Service = '-eximstats'"                 | sudo tee -a /etc/logwatch/conf/logwatch.conf
    logwatch --detail Low --range today
    read -rp "Press [Enter] to return to the menu."
    main
}

function config_ssh {
    # Sets up SSH
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    
    cat > /etc/ssh/sshd_config << EOF
Banner /etc/issue.net
PermitRootLogin no
PermitUserEnvironment no
PermitEmptyPasswords no
Protocol 2
PrintLastLog no
PubkeyAuthentication yes
LoginGraceTime 30
ClientAliveInterval 600
ClientAliveCountMax 1
UsePAM yes
StrictModes yes
IgnoreUserKnownHosts yes
IgnoreRhosts yes
HostBasedAuthentication no
AllowTcpForwarding no
X11Forwarding no
LogLevel VERBOSE
Port 2453
EOF

    # Test and apply configuration
    if sshd -t -f /etc/ssh/sshd_config; then
        systemctl restart sshd.service
        echo "SSH configuration updated successfully"
    else
        echo "Error in SSH config, reverting to backup"
        mv /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
        systemctl restart sshd.service
    fi

    read -rp "Press [Enter] to return to the menu."
    main
}

fix_file_permissions() {
    chmod 640 /etc/shadow
    chmod 644 /etc/passwd
    chmod 640 /var/log
    chmod 640 /var/log/syslog
    chown syslog /var/log/syslog
    chown root /var/log
    chgrp adm /var/log/syslog
    chmod 755 /bin
    chmod 755 /sbin
    chmod 755 /usr/bin
    chmod 755 /usr/sbin
    chmod 755 /usr/local/bin
    chmod 755 /usr/local/sbin
    
    read -rp "Press [Enter] to return to the menu."
    main
}

function config_password_policy() {
    # Install password quality package
    sudo apt-get install -y libpam-pwquality
    
    # Backup PAM files
    sudo cp /etc/pam.d/common-password /etc/pam.d/common-password.bak
    
    # Configure PAM password complexity policies
    sudo sed -i '/pam_pwquality.so/c\password requisite pam_pwquality.so retry=3 minlen=10 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1 reject_username enforce_for_root' /etc/pam.d/common-password
    sudo sed -i '/pam_unix.so/c\password sufficient pam_unix.so use_authtok sha512 shadow remember=5' /etc/pam.d/common-password
    
    # Configure login.defs password aging and login policies
    sed -i 's/^PASS_MAX_DAYS\s\+[0-9]\+$/PASS_MAX_DAYS 90/' "/etc/login.defs"
    sed -i 's/^PASS_MIN_DAYS\s\+[0-9]\+$/PASS_MIN_DAYS 10/' "/etc/login.defs"
    sed -i 's/^PASS_WARN_AGE\s\+[0-9]\+$/PASS_WARN_AGE 7/' "/etc/login.defs"
    sed -i 's/^LOGIN_RETRIES\s\+[0-9]\+$/LOGIN_RETRIES 3/' "/etc/login.defs"
    sed -i 's/^LOGIN_TIMEOUT\s\+[0-9]\+$/LOGIN_TIMEOUT 30/' "/etc/login.defs"
    sed -i 's/^ENCRYPT_METHOD\s\+\w\+$/ENCRYPT_METHOD SHA512/' "/etc/login.defs"
    
    echo "Password policy configured successfully"
    
    # If you want to keep the menu functionality
    read -rp "Press [Enter] to return to the menu."
    main
}

function account_lockout_policy {
    local faillock_file="/usr/share/pam-configs/faillock"
    local faillock_notify_file="/usr/share/pam-configs/faillock_notify"
    
    # Create and configure faillock file
    echo "Configuring $faillock_file..."
    sudo touch "$faillock_file"
    sudo bash -c "cat > $faillock_file" <<'EOL'
Name: Enforce failed login attempt counter
Default: no
Priority: 0
Auth-Type: Primary
Auth:
 [default=die] pam_faillock.so authfail
 sufficient pam_faillock.so authsucc
EOL

    # Create and configure faillock_notify file
    echo "Configuring $faillock_notify_file..."
    sudo touch "$faillock_notify_file"
    sudo bash -c "cat > $faillock_notify_file" <<'EOL'
Name: Notify on failed login attempts
Default: no
Priority: 1024
Auth-Type: Primary
Auth:
 requisite pam_faillock.so preauth
EOL

    # Directly modify common-auth to add faillock configuration
    echo "Configuring PAM auth..."
    sudo sed -i '1i auth required pam_faillock.so preauth silent deny=3 unlock_time=600' /etc/pam.d/common-auth
    sudo sed -i '/pam_unix.so/i auth [default=die] pam_faillock.so authfail' /etc/pam.d/common-auth
    sudo sed -i '/pam_unix.so/a auth sufficient pam_faillock.so authsucc' /etc/pam.d/common-auth
    
    echo "Account lockout policy configured successfully"
    echo "Lockout policy is now active with:"
    echo "- 3 failed attempts results in lockout"
    echo "- 10 minute (600 second) lockout duration"
    
    read -rp "Press [Enter] to return to the menu."
    main
}


function config_sysctl_security {
    # Backup original sysctl.conf
    sudo cp /etc/sysctl.conf /etc/sysctl.conf.bak

    # Apply security settings directly
    sudo tee -a /etc/sysctl.conf << EOF
kernel.randomize_va_space = 2
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_forward = 0
kernel.kptr_restrict = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
EOF

    # Apply changes
    sudo sysctl -p

    read -rp "Press [Enter] to return to the menu."
    main
}

function disable_guest_account {
    local lightdm_conf="/etc/lightdm/lightdm.conf"
    
    # Create directory if it doesn't exist
    sudo mkdir -p "$(dirname "$lightdm_conf")"
    
    # Config LightDM
    sudo tee "$lightdm_conf" > /dev/null <<EOL
[SeatDefaults]
allow-guest=false
greeter-hide-users=true
greeter-show-manual-login=true
autologin-user=none
EOL

    # Also disable guest in GDM if it's installed
    if dpkg -l | grep -q gdm3; then
        sudo mkdir -p /etc/gdm3
        echo "[daemon]
DisallowGuest=true
AutomaticLoginEnable=false" | sudo tee -a /etc/gdm3/custom.conf
    fi

    read -rp "Press [Enter] to return to the menu."
    main
}

function config_sudo_policy {
    # Backup sudoers file
    sudo cp /etc/sudoers /etc/sudoers.bak
    
    # Add secure sudo defaults
    echo 'Defaults env_reset
Defaults mail_badpass
Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Defaults timestamp_timeout=0
Defaults requiretty
Defaults !visiblepw' | sudo EDITOR='tee -a' visudo

    read -rp "Press [Enter] to return to the menu."
    main
}

function secure_ftp {
    read -p "Is FTP required? (y/n): " ftp_required
    
    if [[ $ftp_required != "y" ]]; then
        sudo apt-get purge -y vsftpd
        sudo apt-get autoremove -y
        echo "FTP server removed"
        
        read -rp "Press [Enter] to return to the menu."
        main
    fi

    # If FTP is required, secure it
    local vsftpd_conf="/etc/vsftpd.conf"
    
    # Backup original config
    sudo cp "$vsftpd_conf" "${vsftpd_conf}.bak"
    
    # Configure secure settings
    sudo tee "$vsftpd_conf" > /dev/null <<EOL
# Security Settings
anonymous_enable=NO
local_enable=YES
write_enable=NO
ssl_enable=YES
force_local_logins_ssl=YES
force_local_data_ssl=YES
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
require_ssl_reuse=NO
ssl_ciphers=HIGH
cmds_denied=DELE,RMD,RNFR,RNTO,MKD,STOR,STOU,XMKD,XRMD
listen=YES
listen_ipv6=NO
guest_enable=NO
userlist_enable=YES
userlist_deny=YES
EOL

    sudo mkdir -p /etc/vsftpd
    echo "root" | sudo tee /etc/vsftpd/user_list

    read -rp "Press [Enter] to return to the menu."
    main
}

function config_ip_spoofing_protection {
    # Configure host.conf
    sudo tee /etc/host.conf > /dev/null <<EOL
order bind,hosts
multi on
nospoof on
EOL

    read -rp "Press [Enter] to return to the menu."
    main
}

function managePorts {
    # Checks for open ports.
    touch pids.txt
    touch ports.txt
    netstat -tulpna | awk '{if ($7 != "-" && $7 != "" && $7 != "Address") print $7;}' | sudo tee -a pids.txt   # Puts the process ids into a text file
    netstat -tulpna | awk '{if ($7 != "-" && $7 != "" && $4 != "Local") print $4;}'   | sudo tee -a ports.txt  # Puts the ports into a text file

    touch finalPorts.txt
    while read -r -u 10 pid && read -r -u 11 port
    do
        printf "Port: %s, PID: %s" "$port" "$pid" | sudo tee -a finalPorts.txt  # Puts an outline of each port and the pid/command using it.
    done 10<pids.txt 11<ports.txt

    # Removing unnecessary files.
    rm pids.txt
    rm ports.txt

    # Windows command is netstat -ano, in case that is ever helpful.
    while (true)
    do
        VAR10=0
        VAR11=""
        echo "What port do you want to close?"
        read -r VAR10
        ufw deny "$VAR10"
        echo "Do you want to close another port? [Y/n]"
        read -r VAR11
        if [ "$VAR11" != "Y" ] && [ "$VAR11" != "y" ]; then
            break
        fi
    done

    read -rp "Press [Enter] to return to the menu."
    main
}

function list_prohibited_files {
    # Saving prohibited file paths
    find / -type f -name "*.mp3"   >> audio.txt
    find / -type f -name "*.ac3"   >> audio.txt
    find / -type f -name "*.aac"   >> audio.txt
    find / -type f -name "*.aiff"  >> audio.txt
    find / -type f -name "*.flac"  >> audio.txt
    find / -type f -name "*.m4a"   >> audio.txt
    find / -type f -name "*.m4p"   >> audio.txt
    find / -type f -name "*.midi"  >> audio.txt
    find / -type f -name "*.mp2"   >> audio.txt
    find / -type f -name "*.m3u"   >> audio.txt
    find / -type f -name "*.ogg"   >> audio.txt
    find / -type f -name "*.vqf"   >> audio.txt
    find / -type f -name "*.wav"   >> audio.txt
    find / -type f -name "*.wma"   >> vids.txt
    find / -type f -name "*.mp4"   >> vids.txt
    find / -type f -name "*.avi"   >> vids.txt
    find / -type f -name "*.mpeg4" >> vids.txt
    find / -type f -name "*.gif"   >> pics.txt
    find / -type f -name "*.png"   >> pics.txt
    find / -type f -name "*.bmp"   >> pics.txt
    find / -type f -name "*.jpg"   >> pics.txt
    find / -type f -name "*.jpeg"  >> pics.txt

    read -rp "Press [Enter] to return to the menu."
    main
}

function truetemp {

    # Puts the cron jobs onto the desktop.  (Both user and root)
    for filename in /var/spool/cron/crontabs/*; do
        cat "$filename" | sudo tee -a cronjobs.txt
    done
    cat /etc/crontab | sudo tee -a cronjobs.txt
    # Use 'crontab -r' to remove unnecessary jobs.

    # Preventing IP Spoofing
    echo "nospoof on" | sudo tee -a /etc/host.conf

    # Saving active services
    systemctl list-units --type=service --state=active > services.txt

    read -rp "Press [Enter] to return to the menu."
    main
}

# This function prints a small version of the checklist with a few links.
function checklist {

    printf "Checklist\n"
    printf "    1) Install and run ClamAV\n"
    printf "    2) Install and start ufw\n"
    printf "    3) Update apps\n"
    printf "    4) Read readme, there will definitely be something in there for points\n"
    printf "    5) Check past checklists (Here's one!).\n"
    printf "    6) Help teamates.\n"
    printf "    7) Get teamates to help you.\n"
    printf "    8) Win!!!\n\n"

    read -rp "Press [Enter] to return to the menu."
    main
}

main
