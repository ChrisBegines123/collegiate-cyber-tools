#!/bin/sh

counter=`netstat -apn | grep SYN_RECV | wc -l`

echo "`date`: There were $counter incomplete TCP connections detected." >> /var/log/tcpmonitor.log
