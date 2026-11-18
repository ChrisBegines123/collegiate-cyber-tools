#! /bin/bash

sudo cp ccdcteam /etc/bind/ccdcteam
sudo cp ccdcrevr /etc/bind/ccdcrevr

sudo bash -c 'cat named.conf.local > /etc/bind/named.conf.local'
sudo bash -c 'cat named.conf.options > /etc/bind/named.conf.options'

sudo chown -R bind:bind /var/log/bind9/
sudo chown -R bind:bind /etc/bind/
sudo chmod -R /var/log/bind9/
sudo chmod -R /etc/bind/


# not changed
# named.conf
# named.conf.options
# named.conf.default-zones
# named.conf.external-zones
# named.conf.internal-zones
# named.conf.options.dpkg-dist
# rndc.key
# zones file and files
# zones.rfc1918

# changed
# named.conf.local
# ccdcteam file
# ccdcrevr file
# checkAndApply.sh
# fileReplace.sh
