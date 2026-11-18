#!/usr/bin/env nix
#! nix shell nixpkgs#bash nixpkgs#openssh --command bash
# Author: Collin Dewey
# Description:
# Configures SSH
# Usage:
# ./<Script_Name>

. $(dirname "$0")/helper.sh; if [ -z ${PUBLIC_KEY+x} ]; then exit 1; fi
root_check

if [ -f /usr/lib/systemd/system/sshd.service ] || [ -f /lib/systemd/system/sshd.service ]; then
    NAME=sshd
else
    NAME=ssh
fi

if systemctl is-active --quiet $NAME; then
    systemctl stop $NAME
fi

if ! systemctl is-enabled --quiet $NAME 2>/dev/null; then
    systemctl unmask $NAME
fi

if [ ! -d /etc/ssh.orig ]; then
    mv /etc/ssh /etc/ssh.orig
else
    rm -rf /etc/ssh.old
    mv /etc/ssh /etc/ssh.old
fi
mkdir -p /etc/ssh
mkdir -p /var/empty # Why?

# https://github.com/k4yt3x/sshd_config/
# https://infosec.mozilla.org/guidelines/openssh#modern-openssh-67
echo "AuthorizedPrincipalsFile none
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
GatewayPorts no
KbdInteractiveAuthentication no
KexAlgorithms sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
Macs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
PasswordAuthentication no
AuthenticationMethods publickey
LogLevel VERBOSE
AllowTcpForwarding no
ChallengeResponseAuthentication no
MaxAuthTries 3
PermitEmptyPasswords no
AllowAgentForwarding no
ClientAliveCountMax 2
ClientAliveInterval 300
Compression no
IgnoreRhosts yes
PermitUserEnvironment no
MaxSessions 2
TCPKeepAlive no
Protocol 2
AllowStreamLocalForwarding no
DisableForwarding yes
PermitTunnel no
PermitRootLogin no
StrictModes yes
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
UseDns no
X11Forwarding no
UsePAM no
Banner /etc/issue.net
AuthorizedKeysFile %h/.ssh/authorized_keys_ccdc
AddressFamily any
Port 22
ListenAddress 0.0.0.0
Subsystem sftp $(nix path-info nixpkgs#openssh)/libexec/sftp-server -f AUTHPRIV -l INFO
PrintMotd no # handled by pam_motd
AllowGroups sshusers
#Match User example
#  ForceCommand internal-sftp
#  ChrootDirectory /var/lib/sftp
" > /etc/ssh/sshd_config

cp $(nix path-info nixpkgs#openssh)/etc/ssh/moduli /etc/ssh/moduli
cp $(nix path-info nixpkgs#openssh)/etc/ssh/ssh_config /etc/ssh/ssh_config
ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N ""
create_group sshusers

chown root:root -R /etc/ssh
chmod 644 -R /etc/ssh
chmod 600 /etc/ssh/ssh_host_ed25519_key /etc/ssh/ssh_host_rsa_key

mkdir -p "/etc/systemd/system/$NAME.service.d"
echo "[Service]
Type=simple
EnvironmentFile=
Group=ssh_in
ExecStartPre=
ExecStart=
ExecStart=$(which sshd)
ExecReload=
ExecReload=/bin/kill -HUP \$MAINPID" > "/etc/systemd/system/$NAME.service.d/override.conf"

systemctl daemon-reload
systemctl start $NAME