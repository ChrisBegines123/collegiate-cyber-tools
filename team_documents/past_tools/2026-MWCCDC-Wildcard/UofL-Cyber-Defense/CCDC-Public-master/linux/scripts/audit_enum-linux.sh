#!/usr/bin/env bash
# Author: Noah Tongate @Ap3x
# Description:
#  Audit the linux system and common checks for linux
# Usage:
# ./<SCRIPT NAME>

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

clear
x=0
echo; while [ $x -lt $(tput cols) ];do echo -n '#'; let x=$x+1; done; x=0; echo

echo -e "${GREEN}Permission of Home Folders: ${NC}"; ls -la /home;

echo; while [ $x -lt $(tput cols) ];do echo -n '#'; let x=$x+1; done; x=0; echo

echo -e "${GREEN}Check the PATH envirnment variable: ${NC}"
echo -e "${RED}Default PATH looks like: "
echo -e "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin${NC}"; 
echo $PATH;

echo; while [ $x -lt $(tput cols) ];do echo -n '#'; let x=$x+1; done; x=0; echo

echo -e "${GREEN}Check the all envirnment variable: ${NC}"; env

echo; while [ $x -lt $ ) ];do echo -n '#'; let x=$x+1; done; x=0; echo

echo -e "${GREEN}Check for LD_PRELOAD envirnment variable: ${NC}"; env | grep LD_PRELOAD

echo; while [ $x -lt $(tput cols) ];do echo -n '#'; let x=$x+1; done; x=0; echo

echo -e "${GREEN}Check any odd users: ${NC}"; cat /etc/passwd | grep -v '^#\|^$|^;'

echo; while [ $x -lt $(tput cols) ];do echo -n '#'; let x=$x+1; done; x=0; echo

echo -e "${GREEN}Check any sudoer users: ${NC}"; cat /etc/sudoers | grep -v '^#\|^$|^;'

echo; while [ $x -lt $(tput cols) ];do echo -n '#'; let x=$x+1; done; x=0; echo

echo -e "${GREEN}Check for any odd commands or source of other files: ${NC}"; cat /etc/profile | grep -v '^#\|^$|^;'

echo; while [ $x -lt $(tput cols) ];do echo -n '#'; let x=$x+1; done; x=0; echo

echo -e "${GREEN}Check for odd .bash_aliases: ${NC}"; cat ~/.bash_aliases | grep -v '^#\|^$|^;'

echo; while [ $x -lt $(tput cols) ];do echo -n '#'; let x=$x+1; done; x=0; echo

echo -e "${GREEN}Check for any unnecessary SSH keys: ${NC}"; cat ~/.ssh/authorized_keys 

echo; while [ $x -lt $(tput cols) ];do echo -n '#'; let x=$x+1; done; x=0; echo

echo -e "${GREEN}Check for cron jobs in Crontab List: ${NC}"; crontab -l

echo; while [ $x -lt $(tput cols) ];do echo -n '#'; let x=$x+1; done; x=0; echo

echo -e "${GREEN}Check for cron jobs in Spool: ${NC}"; ls -la /var/spool/cron/

echo; while [ $x -lt $(tput cols) ];do echo -n '#'; let x=$x+1; done; x=0; echo

echo -e "${GREEN}Hidden files in Home Directory? ${NC}"; ls -la ~

echo; while [ $x -lt $(tput cols) ];do echo -n '#'; let x=$x+1; done; x=0; echo

echo -e "${GREEN}Check for any odd backup files: ${NC}"; ls -la /var/backups

echo; while [ $x -lt $(tput cols) ];do echo -n '#'; let x=$x+1; done; x=0; echo

# Dependent on OS
#  Ubuntu - cat /etc/apt/sources.list
#  Debian - cat /etc/apt/sources.list
#  CentOS - ls -la /etc/yum.repos.d/
echo -e "${GREEN}Check for odd repositories:  ${NC}";  cat /etc/apt/sources.list | grep -v -i '^#'

echo; while [ $x -lt $(tput cols) ];do echo -n '#'; let x=$x+1; done; x=0; echo

echo -e "${GREEN}Check for open ports:  ${NC}";  ss -tulpn

echo; while [ $x -lt $(tput cols) ];do echo -n '#'; let x=$x+1; done; x=0; echo

echo -e "${GREEN}Check for PAM backdoor:  ${NC}";  
echo -e "${RED}Look in /lib/x86_64-linux-gnu/security/ ${NC}";  
echo -e "${RED}Look for any odd files using this command: grep -rnw '/etc/pam.d/ ' -ie '^auth' ${NC}";
echo; while [ $x -lt $(tput cols) ];do echo -n '#'; let x=$x+1; done; x=0; echo
