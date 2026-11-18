#!/usr/bin/env bash

set -euo pipefail

# Used for coloring text in the script

red="\033[31m"
green="\033[32m"
yellow="\033[1;33m"
blue="\033[34m"
reset="\033[0m"

green_text() {
  echo -e "${green}${1}${reset}"`
}

blue_text() {
  echo -e "${blue}${1}${reset}"
}

red_text() {
  echo -e "${red}${1}${reset}"
}

yellow_text() {
  echo -e "${yellow}${1}${reset}"
}

# Logging function
LOGNAME="hardener_script.log" # Should be changed by script using this function

logger() {
  text=$1
  echo "$1" >> ${LOGNAME}
}

