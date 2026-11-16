#!/bin/bash
#-----
#Root Check
#-----
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root!" >&2
    exit 1
fi
#-----
#-----
# In Case Of Emergency
#-----
# bash trap command can execute a subroutine when X condition occurs
trap bashtrap INT
# bash trap function is executed when CTRL-C is pressed:
bashtrap()
{
    \n
    echo "CTRL+C Detected! Exiting Script Early!"

    exit 1
}
#-----
#-----
#SSH Killer and Clearer
#-----
#make callable
chmod a+x ./FromOurGithub/WSSH_Killer_Clearer.sh
#Call
/bin/bash ./FromOurGithub/WSSH_Killer_Clearer.sh
#-----
#-----
#Disable Cron
#-----
chmod a+x ./FromOurGithub/WCronDisable.sh
/bin/bash ./FromOurGithub/WCronDisable.sh
echo "Cron disabled, recocmended to remove cron if no necessary jobs"
#-----
#-----
#Login Banner
#-----
chmod a+x ./FromOurGithub/WLoginBanner.sh
/bin/bash ./FromOurGithub/WLoginBanner.sh
#-----
#-----
#Auditing packages
#-----
#make callable
chmod a+x ./FromOurGithub/audit_packages.sh
#Call
/bin/bash ./FromOurGithub/audit_packages.sh
#-----
#-----
# Backing up some important stuff
#-----
chmod a+x ./FromOurGithub/WBackupEcom.sh
/bin/bash ./FromOurGithub/WBackupEcom.sh
#-----
#-----
# Setting Package Manager
#-----
# Set default value for pkmt
pkmtc=0

read -p "Do you want to use apt (1) or dnf (2)?" -n 1 c

# Check if user has provided a value for pkmt
if [ -n "$c" ]; then
	if [ "$c" == "1" ] || [ "$c" == "2" ]; then
		pkmtc=$c
	else
		echo "Invalid value for pkmt. Please enter 1 (for apt) or 2 (for dnf)."
		exit 1
	fi
fi

# Set the package manager (pkmt) based on user choice (c) 
case $pkmtc in
	1) pkmt=apt ;;
	2) pkmt=dnf ;;
	*) echo "Invalid value for pkmt. Please enter 1 (for apt) or 2 (for dnf)."
		exit 1 ;;
esac

# Declaration of package manager
echo "The package manager that has been chosen is: $pkmt"
#-----
#-----
#echo "Checking validity of package manager"
#case $pkmt in
#  apt) chmod a+x ./FromOurGithub/WaptApt-Check.sh
# /bin/bash ./FromOurGithub/WaptApt-Check.sh
# echo "Apt is probibly okay, you're about to find out.";;
#  dnf) echo "I lied lol we're not checking the packagemanger to see if it's ok."
#esac
#-----
# Upgrading System
#-----
sudo $pkmt update -y && sudo $pkmt upgrade -y
#-----
#-----
# Fail2Ban Setup
#-----
case $pkmt in
  apt)chmod a+x ./FromOurGithub/WaptFail2Ban.sh
 /bin/bash ./FromOurGithub/WaptFail2Ban.sh ;;
  dnf)chmod a+x ./FromOurGithub/WdnfFail2Ban.sh
 /bin/bash ./FromOurGithub/WdnfFail2Ban.sh ;;
esac
#-----
#-----
# ClamAV Setup
#-----
case $pkmt in
  apt) chmod a+x ./FromOurGithub/WaptClamAVService.sh
 /bin/bash ./FromOurGithub/WaptClamAVService.sh ;;
  dnf) chmod a+x ./FromOurGithub/WdnfClamAVService.sh
 /bin/bash ./FromOurGithub/WdnfClamAVService.sh ;;
esac
#-----
#-----
#Wazuh Agent Install
#-----
case $pkmt in
  apt)chmod a+x ./FromOurGithub/WaptWazuhAgent.sh
 /bin/bash ./FromOurGithub/WaptWazuhAgent.sh ;;
  dnf)chmod a+x ./FromOurGithub/WdnfWazuhAgent.sh
 /bin/bash ./FromOurGithub/WdnfWazuhAgent.sh ;;
esac
echo "Wazuh Agent Installed, Probibly works"
#-----
#-----
#Installing rkhunter for later use
#-----
sudo $pkmt install rkhunter -y
echo "rkhunter installed for later use"
#-----
#-----
# Firewall Setup
#-----
#make callable
chmod a+x ./FromOurGithub/Wsetup_firewall.sh
#Call
/bin/bash ./FromOurGithub/Wsetup_firewall.sh
echo "firewall.sh finished?"
