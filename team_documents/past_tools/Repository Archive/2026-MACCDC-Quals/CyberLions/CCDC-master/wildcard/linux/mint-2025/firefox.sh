#!/bin/bash

### Mint

### This should not be run as root!!
# Depends on user.js being in user's home dir and starting in home dir

PROFILE_PATH=$(echo ~/.mozilla/firefox/$(grep Default ~/.mozilla/firefox/profiles.ini | grep -v '^#' | head -n 1 | cut -d= -f2))

git clone https://github.com/arkenfox/user.js.git

cd user.js
cp prefsCleaner.sh user.js $PROFILE_PATH

cd $PROFILE_PATH
echo 1 | bash prefsCleaner.sh

cd ~/user.js
echo "Y" | ./updater.sh

