#!/bin/bash

clear
echo "  ______________________________________________________________________________________  "
echo " |OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO| "
echo " |O                                                                                    O| " 
echo " |O                 _______ ______          __  __    ____  ______ _______             O| "
echo " |O                |__   __|  ____|   /\   |  \/  |  |  _ \|  ____|__   __|/\          O| "
echo " |O                   | |  | |__     /  \  | \  / |  | |_) | |__     | |  /  \         O| "
echo " |O                   | |  |  __|   / /\ \ | |\/| |  |  _ <|  __|    | | / /\ \        O| "
echo " |O                   | |  | |____ / ____ \| |  | |  | |_) | |____   | |/ ____ \       O| "
echo " |O                   |_|  |______/_/    \_\_|  |_|  |____/|______|  |_/_/    \_\      O| "          
echo " |O                                                                                    O| "  
echo " |O                                                                                    O| " 
echo " |OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO| "
echo " |O                                                                                    O| "
echo " |O                                                                                    O| "            
echo " |O                             'Summa, Lumma, Dumma, and Summa'                       O| "                                    
echo " |O                                                                                    O| "
echo " |O                                                                                    O| "
echo " |OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO| "

ufw enable

# Delete prohibited files

#cd / --Uncomment on actual script run
echo "Removing media files..."
find . -name "*.mp3" -type f -delete &> /dev/null
find . -name "*.mp4" -type f -delete &> /dev/null
find . -name "*.jpeg" -type f -delete &> /dev/null
find . -name "*.png" -type f -delete &> /dev/null
find . -name "*.dds" -type f -delete &> /dev/null
find . -name "*.jpg" -type f -delete &> /dev/null

if ! command -v nano &> /dev/null
then
    echo "Nano file editor already found. Beginning hacker tool removal."
else
    apt install nano -y &> /dev/null
    echo "Nano Installed"
fi

if ! command -v nmap &> /dev/null
then
    echo "Nmap not found, moving on..."
else
    apt remove nmap -y &> /dev/null
    echo "Nmap removed"
fi

if ! command -v hydra &> /dev/null
then
    echo "Hydra not found, moving on..."
else
    apt remove hydra -y &> /dev/null
    echo "Hydra removed"
fi

if ! command -v keylogger &> /dev/null
then
    echo "keylogger not found, moving on..."
else
    apt remove keylogger -y &> /dev/null
    echo "keylogger removed"
fi

if ! command -v metasploit &> /dev/null
then
    echo "metasploit not found, moving on..."
else
    apt remove metasploit -y &> /dev/null
    echo "metasploit removed"
fi

if ! command -v hashcat &> /dev/null
then
    echo "hashcat not found, moving on..."
else
    apt remove hashcat -y &> /dev/null
    echo "hashcat removed"
fi

apt update -y &> /dev/null
apt update firefox -y &> /dev/null

read -p "Would you like to use the auto SSH secure or manual? [auto/man] " dec

if [ $dec == "auto" ]
then
    if ! command -v python3 &> /dev/null
    then
        apt install python3 -y &> /dev/null
    else
        python3 ./editsshd.py
    fi
else
    echo "---------------------------------"
    echo "                                 "
    echo "       Starting SSH Manual       "
    echo "                                 "
    echo "    At any time press a key to   "
    echo "     continue to the next step   "
    echo "                                 "
    echo "---------------------------------"
    echo "                                 "
    echo "Step 1: Navigate  to /etc/ssh using cd"
    read -p ""
    echo "Step 2: Edit the sshd_config file using nano. Ex: nano sshd_config"
    read -p ""
    echo "Step 3a: Find the following line: 'Port 22' or '#Port 22' and change it to 'Port 2025'"
    read -p ""
    echo "Step 3b: Add the following line to the bottom of the file: 'ClientAliveInterval 300'"
    read -p ""
    echo "Step 3c: Add the following line to the bottom of the file: 'ClientAliveCountMax 0'"
    read -p ""
    echo "Step 3d: Find the following line and edit or add it to the bottom of the file if it does not exist: 'PermitEmptyPasswords no'"
    read -p ""
    echo "Step 3e: Go to the bottom of the file and for each administrative user add this line: 'AllowUsers AdminUser'"
    read -p ""
    echo "Step 3f: Find and edit the following line: 'PermitRootLogin no'"
    read -p ""
    echo "Step 3g: Find and edit the following line or add it the bottom of the file if it does not exist: 'Protocol 2'"
    ufw allow 2025
    service ssh restart
fi
