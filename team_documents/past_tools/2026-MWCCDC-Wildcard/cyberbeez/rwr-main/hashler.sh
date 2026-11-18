#!/bin/bash
#This script will run a md5 hash backup and check job.
#To use this script, put the filename as an arguement while running the script.

file=$1
while true;
do
md5sum $file > $file"_hashler.md5"
sleep 300 #5mins
md5sum -c $file"_hashler.md5"
done
