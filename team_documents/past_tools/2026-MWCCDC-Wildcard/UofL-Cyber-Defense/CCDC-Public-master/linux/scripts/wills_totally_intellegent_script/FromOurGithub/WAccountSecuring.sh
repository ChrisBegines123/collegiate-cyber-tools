#!/bin/bash

#-----
# IMPORTANT VARIABLES TO SET
#-----
su="U"
#-----
#-----
#Securing Root Account and Other Such Security Measures
#-----
echo "Enter new password for $su"
    passwd $su </dev/tty
chmod a+x ./FromOurGithub/helper.sh
/bin/bash ./FromOurGithub/helper.sh
chmod a+x ./FromOurGithub/setup_users.sh
/bin/bash ./FromOurGithub/setup_users.sh
chmod a+x ./FromOurGithub/setup_syslog.sh
/bin/bash ./FromOurGithub/setup_syslog.sh
#-----
