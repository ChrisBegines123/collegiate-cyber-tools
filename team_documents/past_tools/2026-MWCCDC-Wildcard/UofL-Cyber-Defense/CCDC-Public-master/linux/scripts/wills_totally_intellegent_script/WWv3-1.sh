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
# IMPORTANT VARIABLES TO SET
#-----
su="U"
#-----
#-----
#Securing Admin Account and OSetting Up Helper
#-----
echo "Enter new password for $su"
    passwd $su </dev/tty
chmod a+x ./FromOurGithub/helper.sh
/bin/bash ./FromOurGithub/helper.sh
#-----
#-----
#Securing Root Account and Other Such Security Measures
#-----
echo "Enter new password for $su"
    passwd $su </dev/tty
chmod a+x ./FromOurGithub/setup_users.sh
/bin/bash ./FromOurGithub/setup_users.sh
chmod a+x ./FromOurGithub/setup_syslog.sh
/bin/bash ./FromOurGithub/setup_syslog.sh
#-----
