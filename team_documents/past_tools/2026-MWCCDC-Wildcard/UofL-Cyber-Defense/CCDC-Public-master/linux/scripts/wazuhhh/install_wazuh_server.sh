#!/usr/bin/env bash
#
# installs latest version of wazuh


if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" >&2
    exit 1
fi

if ! command -v git &> /dev/null
then
    echo "installing git. . ."
    yum install git
    exit 1
fi

if ! command -v docker &> /dev/null
then
    echo "installing docker. . ."
    yum install -y yum-utils
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum install docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl start docker
    exit 1
fi

sysctl -w vm.max_map_count=262144


if [ ! -d "wazuh-docker" ]; then

    git clone https://github.com/wazuh/wazuh-docker.git -b v4.14.2
else
    echo "directory 'wazuh-docker' already exists - skipping clone."

    cd wazuh-docker && git pull origin v4.14.2
    cd ..
fi

cd ./wazuh-docker/single-node || { echo "Failed to enter wazuh-docker directory"; exit 1; }

docker compose -f generate-indexer-certs.yml run --rm generator

docker compose up -d
