#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Use sudo."
   exit 1
fi


cat << 'EOF' > /etc/motd
*************************************************************
* NOTICE: AUTHORIZED USE ONLY                              *
* This system is the property of [Organization Name].       *
* Access is restricted to authorized users. By continuing,  *
* you consent to monitoring and recording of all activities.*
* Unauthorized access or misuse is strictly prohibited and  *
* may result in criminal prosecution or disciplinary action.*
* There is no right to privacy on this system.              *
*************************************************************
EOF

echo "Login banner successfully updated in /etc/motd"
