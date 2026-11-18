#!/bin/bash

sudo /etc/init.d/cron stop
#Disabling user access to cron (thanks Collin!)
move /usr/sbin/cron
cut -d: -f1 /etc/passwd | tail -n+2 >> /etc/cron.deny
