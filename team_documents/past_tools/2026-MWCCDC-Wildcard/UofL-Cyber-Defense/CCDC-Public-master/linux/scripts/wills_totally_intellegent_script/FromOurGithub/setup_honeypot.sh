#!/usr/bin/env nix
#! nix shell nixpkgs#bash nixpkgs#honeytrap --command bash
# Author: Collin Dewey
# Description:
# It's a trap!
# Usage:
# ./<Script_Name>

#credentials=["root:root", "root:password"]

. $(dirname "$0")/helper.sh; if [ -z ${PUBLIC_KEY+x} ]; then exit 1; fi
root_check
nix_shell_guard

if [ ! -d /etc/honeytrap ]; then
    mkdir -p /etc/honeytrap
    echo '''
[listener]
type="socket"

[service.ssh-simulator]
type="ssh-simulator"
motd="UNAUTHORIZED ACCESS TO THIS DEVICE IS PROHIBITED. You must have explicit, authorized permission to access or configure this device. Unauthorized attempts and actions to access or use this system may result in civil and/or criminal penalties. All activities performed on this device are logged and monitored.\n"

[[port]]
port="tcp/22"
services=["ssh-simulator"]

[service.telnet]
type="telnet"
prompt=">"
motd="UNAUTHORIZED ACCESS TO THIS DEVICE IS PROHIBITED. You must have explicit, authorized permission to access or configure this device. Unauthorized attempts and actions to access or use this system may result in civil and/or criminal penalties. All activities performed on this device are logged and monitored.\n"

[[port]]
port="tcp/23"
services=["telnet"]

[channel.console]
type="console"

[channel.log]
type="file"
filename="/var/log/honeytrap.log"
maxsize=536870912

[[filter]]
channel=["console"]
services=["ssh-simulator telnet"]

[[filter]]
channel=["log"]
services=["ssh-simulator telnet"]

[[logging]]
output="stdout"
level="debug"''' > /etc/honeytrap/config.toml
fi

if command -v systemctl >/dev/null 2>&1; then
    echo "
[Unit]
Description=Honeytrap
After=network-online.target

[Service]
Type=simple
Group=honeypot_in
ExecStart=$(which honeytrap) --data /etc/honeytrap

[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/honeytrap.service
    systemctl enable honeytrap.service
    systemctl start honeytrap.service
else
    honeytrap --config /etc/honeytrap/config.toml --data /etc/honeytrap
fi
