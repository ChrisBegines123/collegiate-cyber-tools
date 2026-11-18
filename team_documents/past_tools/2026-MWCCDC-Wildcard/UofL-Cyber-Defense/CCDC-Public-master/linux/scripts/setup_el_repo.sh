#!/usr/bin/env bash
# Author: Collin Dewey
# Description:
# Sets up the ELRepo
# Usage:
# ./<Script_Name>

. $(dirname "$0")/helper.sh; if [ -z ${PUBLIC_KEY+x} ]; then exit 1; fi
root_check

rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org

if [ -f /etc/centos-release ] && grep -q "CentOS release 7" /etc/centos-release; then
    rpm -Uvh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    sed -i "s|enabled=0|enabled=1|g" /etc/yum.repos.d/elrepo.repo 
fi