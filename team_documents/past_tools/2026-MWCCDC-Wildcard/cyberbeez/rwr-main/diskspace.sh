#!/bin/sh

#alert threshold
THRESHOLD=70

#read the hard drive space of filesystems that don't include Filesystem, tmpfs, or cdrom
#awk processes the output to contain just the filesystem name and the percent full
df -H | grep -vE '^Filesystem|tmpfs|cdrom' | awk '{ print $5 " " $1 }' | while read -r output;

#loop through each filesystem
do
    #remove the percent sign before the percentage
    usepercent=$( echo "$output" | awk '{ print $1}' | cut -d '%' -f1 )
    #pull out just the partition into a variable
    partition=$( echo "$output" | awk '{ print $2 }' )
    #if the percentage is greater than or equal to the threshold
    #then use logger to log a message to syslog
    if [ $usepercent -ge $THRESHOLD ]; then
        logger "Running out of space on \"$partition ($usepercent%)\""
    fi
done
