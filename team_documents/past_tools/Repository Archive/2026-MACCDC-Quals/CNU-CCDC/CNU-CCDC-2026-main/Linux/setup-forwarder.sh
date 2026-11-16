#!/usr/bin/env bash

set -euo pipefail

# Logging function
LOGNAME="hardener_script.log" # Should be changed by script using this function

logger() {
  text=$1
  echo "$1" >> ${LOGNAME}
}

# Needed to grab our logs
src_dir=$(dirname "$(realpath "$0")")
source "${src_dir}/commonFuctions.sh"
host=$(hostname)


echo "Starting Splunk Universal Forwarder setup..."
logger "Starting Splunk Universal Forwarder setup..."

setup_splunk() {
# 6. Prompt the user for the Splunk server IP
  #splunk_server_ip="172.20.242.20"
  read -p "Enter the IP address of the Splunk server (Should be: 172.20.242.20): " splunk_server_ip

  # 7. Configure the Forwarder to Send Logs
  echo "Configuring Splunk Forwarder inputs..."
  cat <<EOF > /opt/splunkforwarder/etc/system/local/inputs.conf

  [monitor:///var/log/auth.log]
  disabled = false
  index = security
  sourcetype = linux_secure

  [monitor:///var/log/syslog]
  index = system
  sourcetype = syslog

  [monitor:///var/log/kern.log]
  index = system
  sourcetype = kernel

  [monitor:///var/log/audit/audit.log]
  index = security
  sourcetype = auditd

  [monitor:///var/log/nginx/access.log]
  index = web
  sourcetype = nginx_access

  [monitor:///var/log/nginx/error.log]
  index = web
  sourcetype = nginx_errorNETLAB+™

  [monitor:///var/log/iptables.log]NETLAB+™
  index = firewall
  sourcetype = iptables

  [monitor:///var/log/cron]
  index = system
  sourcetype = cron

  [monitor://${src_dir}/${host}.csv]
  disabled = false
  index = csv_logs
  sourcetype = csv_data
EOF

  # 8. Define props.conf for CSV field extraction
  echo "Configuring Splunk props for CSV parsing..."
  cat <<EOF > /opt/splunkforwarder/etc/system/local/props.conf
  [csv_data]
  INDEXED_EXTRACTIONS = csv
  FIELD_DELIMITER = ,
  HEADER_FIELD_LINE_NUMBER = 1
  TIMESTAMP_FIELDS = timestamp
  TIME_FORMAT = %Y-%m-%d %H:%M:%S
  SHOULD_LINEMERGE = false
EOF

  # 9. Define the destination Splunk server with the user-provided IP
  echo "Configuring Splunk Forwarder outputs..."
  cat <<EOF > /opt/splunkforwarder/etc/system/local/outputs.conf
  [tcpout]
  defaultGroup = default-autolb-group

  [tcpout:default-autolb-group]
  server = $splunk_server_ip:2510
EOF

  # 10. Restart the Splunk Universal Forwarder to apply changes
  echo "Restarting Splunk Universal Forwarder..."
  /opt/splunkforwarder/bin/splunk restart

  echo "Splunk Universal Forwarder setup completed!"

}

install_splunk() {
  # 1. Detect the Operating System and Architecture
  OS=$(uname -s)
  ARCH=$(uname -m)

  # Define the download URL based on OS and architecture
  if [[ "$OS" == "Linux" ]]; then
      if [[ "$ARCH" == "x86_64" ]]; then
          DOWNLOAD_URL="https://mscampus.wustl.edu/Splunk/UniversalForwarder/Linux/64-bit/splunkforwarder-9.4.4-f627d88b766b-linux-amd64.tgz"
      else
        echo "Unsupported Linux architecture $ARCH. Exiting..."
        exit 1
      fi
    else
      echo "Unsupported operating system $OS. Exiting..."
      exit 1
  fi

  # 2. Download the Splunk Universal Forwarder
  echo "Downloading Splunk Universal Forwarder from $DOWNLOAD_URL..."
  wget --header="User-Agent: Mozilla/5.0" -O /tmp/splunkforwarder.tgz "$DOWNLOAD_URL"

  # Check if download was successful
  if [[ $? -ne 0 ]]; then
      echo "Failed to download Splunk Universal Forwarder. Exiting..."
      exit 1
  fi

  # 3. Extract the downloaded file
  echo "Extracting Splunk Universal Forwarder..."
  sudo tar -xzvf /tmp/splunkforwarder.tgz -C /opt/ || { echo "Failed to extract Splunk Universal Forwarder. Exiting..."; exit 1; }

  echo "creating splunk user"
  useradd -m splunk

  echo "Preping splunk folder"
  export SPLUNK_HOME="/opt/splunkforwarder"
  mkdir -p $SPLUNK_HOME
  chown -R splunk:splunk $SPLUNK_HOME


  # 4. Start the Splunk Universal Forwarder
  echo "Starting Splunk Universal Forwarder..."
  cd /opt/splunkforwarder/bin
  sudo ./splunk start --accept-license

  # 5. Enable Splunk to start on boot
  echo "Enabling Splunk Universal Forwarder to start on boot..."
  sudo ./splunk enable boot-start
  setup_splunk
  
}

apt_based() {
  echo "Checking if wget, tar, or unzip is not installed."  
  logger "Checking if wget, tar, or unzip is not installed."
  # Ensure required tools are installed (wget, tar, unzip)
  if ! command -v wget &> /dev/null || ! command -v tar &> /dev/null || ! command -v unzip &> /dev/null; then
    echo "wget, tar, or unzip is not installed. Installing..."
    logger "wget, tar, or unzip is not installed. Installing..." 
    sudo apt-get update && apt-get install wget tar unzip -y || { echo "Failed to install required tools"; logger "Failed to install required tools"; exit 1; }
  fi
  echo "tools found or installed"
  logger "tools found or installed"
  install_splunk
}

dnf_based() {
  echo "Checking if wget, tar, or unzip is not installed." 
  logger "Checking if wget, tar, or unzip is not installed."
  # Ensure required tools are installed (wget, tar, unzip)
  if ! command -v wget &> /dev/null || ! command -v tar &> /dev/null || ! command -v unzip &> /dev/null; then
    echo "wget, tar, or unzip is not installed. Installing..."
    logger "wget, tar, or unzip is not installed. Installing..." 
    sudo dnf upgrade --refresh && dnf install wget tar unzip -y || { echo "Failed to install required tools"; logger "Failed to install required tools"; exit 1; }
  fi
  echo "tools found or installed"
  logger "tools found or installed"
  install_splunk
}


while true; do
  printf "1.| apt\n2.| dnf\n3.| other \n"
  printf "\nWhat package manager are you using?: "
  read -r package_manager_selection
  if [ "$package_manager_selection" = "1" ]; then
      logger "on apt_based" 
      apt_based
      break 
    elif [ "$package_manager_selection" = "2" ]; then
      logger "on dnf_based" 
      dnf_based
      break
    elif [ "$package_manager_selection" = "3" ]; then
      swap_size=8
      break
    else
      red_text "Invalid selection $package_manager_selection"
      continue
    fi

done

