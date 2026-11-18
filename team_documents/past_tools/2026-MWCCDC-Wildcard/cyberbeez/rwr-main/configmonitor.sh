#!/bin/sh

files=("/etc/sysctl.conf" "/etc/security/limits.conf" "/etc/syslog.conf" "/etc/network/interfaces" "/etc/resolv.conf" "/etc/passwd" "/etc/group" "/etc/shadow" "/etc/fstab" "/etc/mtab")
backup="./backup"

if [ ! -d $backup ]; then
    mkdir $backup
    mkdir "$backup"/etc
    mkdir "$backup"/etc/security
    mkdir "$backup"/etc/network
fi

for file in $files
    do
        if [ ! -f $backup$file ]; then
            cp $file $backup$file
        fi
    done

while :
do
    for file in $files
    do
        echo "$file": >> ./differences.txt
        echo `diff $file $backup$file` >> ./differences.txt
    done
    
    sleep 5m
done
