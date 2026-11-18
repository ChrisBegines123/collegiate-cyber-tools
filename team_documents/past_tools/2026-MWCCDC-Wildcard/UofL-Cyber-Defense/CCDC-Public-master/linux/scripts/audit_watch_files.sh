#!/usr/bin/env bash
# Author: Noah Tongate @Ap3x
# Description:
# Audit the linux system and common checks for linux
# Usage:
# ./<SCRIPT NAME> -p <PATH TO AUDIT> -o <OUTPUT FILE>

tailStr="ORIG"

while getopts p: flag
do
    case "${flag}" in
        p) path=${OPTARG};;
#        o) output=${OPTARG};;
    esac
done

origFilename="/tmp/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)"
tempFilename="/tmp/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)"

find "$path" -type f -print0 | xargs -0 sha1sum > $origFilename
chmod 600 $origFilename

while true; do

    find "$path" -type f -print0 | xargs -0 sha1sum > $tempFilename
    chmod 600 $tempFilename
    if [[ $(diff $tempFilename $origFilename) ]]
    then
        outputDiff=$(diff $tempFilename $origFilename)
        wall "FILE CHANGE IN $path $outputDiff"
        echo "FILE CHANGE IN $path $outputDiff ----> $(date)" >> /var/log/filewatch.log
        chmod 600 /var/log/filewatch.log
        mv $tempFilename $origFilename
    fi
    sleep 2

done