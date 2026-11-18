#!/bin/bash

#Remove the current apt and apptitude installs and configs
    dpkg -r apt
    dpkg -r apptitude
    # Install apt using the downloaded packages
    cd /opt/ccdc/apt+apptitude_installers
    dpkg --install /opt/ccdc/apt+apptitude_installers/aptitude-common_0.8.13-5ubuntu5_all.deb
    dpkg --install /opt/ccdc/apt+apptitude_installers/apt-transport-https_1.6.1_all.deb
    # Update apt database and install apt
    apt-get update
    apt-get install apt
