#!/usr/bin/env bash
# Author: Noah Tongate @Ap3x
# Description:
#  Watchs for any Red Team connections and logs it
# Usage:
# ./<SCRIPT NAME>

LOGFILE="/var/log/logconnection.log"
TEMPFILE1="/tmp/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)"
TEMPFILE2="/tmp/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)"

ss -tupln | grep -v -i "^Netid" > $LOGFILE
date >> $LOGFILE
while true; do
	sleep 2s
	ss -tupln | grep -v -i "^Netid" > $TEMPFILE2
	cat $LOGFILE | grep -ie "^tcp" -ie "^udp" > $TEMPFILE1
	diff -b $TEMPFILE1 $TEMPFILE2 | grep ">" | grep -e tcp -e udp | sed 's/^..//' >> $LOGFILE
	if [[ $(diff -b $TEMPFILE1 $TEMPFILE2 | grep ">" | grep -e tcp -e udp | sed 's/^..//')  ]]; then
		date >> $LOGFILE
	fi
done
rm $TEMPFILE1
rm $TEMPFILE2
