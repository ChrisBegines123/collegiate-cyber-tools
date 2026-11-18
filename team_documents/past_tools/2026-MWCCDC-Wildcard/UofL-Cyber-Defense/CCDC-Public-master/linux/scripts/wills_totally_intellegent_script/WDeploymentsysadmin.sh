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
# Make Important Dir
#-----
sudo mkdir /opt/ccdc
#-----
#-----
# IMPORTANT VARIABLES TO SET
#-----
su="sysadmin"
#-----
#-----
#Securing Admin Account and Setting Up Helper
#-----
echo "Enter new password for $su"
    passwd $su </dev/tty
chmod a+x ./FromOurGithub/helper.sh
/bin/bash ./FromOurGithub/helper.sh
#-----
#-----
# Account Securing and Basic Loging
#-----
#make callable
chmod a+x ./FromOurGithub/WAccountSecuring.sh
#Call
/bin/bash ./FromOurGithub/WAccountSecuring.sh
