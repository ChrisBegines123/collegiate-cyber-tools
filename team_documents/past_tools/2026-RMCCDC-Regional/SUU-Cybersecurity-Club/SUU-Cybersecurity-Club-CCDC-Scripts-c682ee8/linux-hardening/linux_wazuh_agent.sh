#!/bin/bash

# linux_wazuh_agent.sh

#! /bin/bash

# Get ip address
Wazuh_IP="$1"
if [[ -z "$Wazuh_IP" ]]; then
    echo "Error: No Wazuh_IP provided."
    exit 1
fi

# Get package manager
package_manager="$2"
if [[ -z "$package_manager" ]]; then
    echo "Error: No package manager provided."
    exit 1
fi

Nic="$(ip -o -4 route show to default | awk '{print $5}')"

# yum install
yum_install(){
    # Import the GPG key:
    rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH

    # Add the repository:
    cat > /etc/yum.repos.d/wazuh.repo << EOF
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-\$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
EOF

    # Install the Wazuh agent:
    WAZUH_MANAGER="$Wazuh_IP" yum install wazuh-agent

	# Enable and start the agent:
	systemctl daemon-reload
	systemctl enable wazuh-agent
	systemctl start wazuh-agent

	# Install dependencies for Suricata:
	yum install epel-release yum-plugin-copr

	# Add the repo:
	yum copr enable @oisf/suricata-7.0

	# Install suricata:
	yum install suricata

	# Reconfigure suricata service to use the updated nic:
	sed -i "s/eth0/$Nic/" /etc/sysconfig/suricata
}

# apt install
apt_install(){
	# Install curl
	apt -y install curl

    # Install the GPG key:
    curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && chmod 644 /usr/share/keyrings/wazuh.gpg

    # Add the repository:
    echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | tee -a /etc/apt/sources.list.d/wazuh.list

    # Update the package information:
    apt-get update

    # Install the Wazuh agent:
    WAZUH_MANAGER="$Wazuh_IP" apt-get install wazuh-agent

	# Enable and start the agent:
	systemctl daemon-reload
	systemctl enable wazuh-agent
	systemctl start wazuh-agent

	# Add the repo:
	add-apt-repository ppa:oisf/suricata-stable

	# Install suricata:
	apt update
	apt install suricata
}

# zypper install
zypper_install(){
    # Import the GPG key:
    rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH

    # Add the repository:
    cat > /etc/zypp/repos.d/wazuh.repo << EOF
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
EOF

    # Refresh the repository:
    zypper refresh

    # Install the Wazuh agent:
    WAZUH_MANAGER="$Wazuh_IP" zypper install wazuh-agent
}

case "$package_manager" in
    apt)
        apt_install
        ;;
    yum)
        yum_install
        ;;
    zypper)
        zypper_install
        ;;
    *)
        echo "Error: Unsupported package manager."
        exit 1
        ;;
esac

# Add the correct interface for suricata:
sed -i "s/interface: eth0/interface: $Nic/g" /etc/suricata/suricata.yaml

# Update rules and restart:
suricata-update
systemctl restart suricata

# Update the ossec.conf to ingest suricata logs:
cat >> /var/ossec/etc/ossec.conf << EOF
<ossec_config>
  <localfile>
    <log_format>json</log_format>
    <location>/var/log/suricata/eve.json</location>
  </localfile>
</ossec_config>
EOF
