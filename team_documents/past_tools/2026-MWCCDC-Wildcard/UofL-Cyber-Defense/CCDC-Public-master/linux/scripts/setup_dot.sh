#!/usr/bin/env nix
#! nix shell nixpkgs#bash nixpkgs#stubby nixpkgs#getdns nixpkgs#openssl --command bash
# Author: Collin Dewey
# Description:
# Sets up DNS over TLS using Stubby
# Usage:
# ./<Script_Name>

. $(dirname "$0")/helper.sh; if [ -z ${PUBLIC_KEY+x} ]; then exit 1; fi
root_check
nix_shell_guard

if [ ! -d /etc/stubby ]; then
    mkdir -p /etc/stubby/cache
    echo "
log_level: GETDNS_LOG_NOTICE
resolution_type: GETDNS_RESOLUTION_STUB
dns_transport_list:
  - GETDNS_TRANSPORT_TLS
#  - GETDNS_TRANSPORT_UDP
#  - GETDNS_TRANSPORT_TCP
#tls_authentication: GETDNS_AUTHENTICATION_NONE
tls_authentication: GETDNS_AUTHENTICATION_REQUIRED
tls_query_padding_blocksize: 128
edns_client_subnet_private : 1
round_robin_upstreams: 1
idle_timeout: 10000
tls_ca_path: "/etc/ssl/certs/"
listen_addresses:
  - 127.0.8.53
dnssec: GETDNS_EXTENSION_TRUE
appdata_dir: "/etc/stubby/cache"
upstream_recursive_servers:
  - address_data: 185.49.141.37
    tls_port: 443
    tls_auth_name: "getdnsapi.net"
    tls_pubkey_pinset:
      - digest: "sha256"
        value: $(echo | openssl s_client -connect '185.49.141.37:443' 2>/dev/null | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64)
  - address_data: 89.234.186.112
    tls_port: 443
    tls_auth_name: "dns.neutopia.org"
    tls_pubkey_pinset:
      - digest: "sha256"
        value: $(echo | openssl s_client -connect '89.234.186.112:443' 2>/dev/null | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64)
    " > /etc/stubby/stubby.yml
fi


if command -v systemctl >/dev/null 2>&1; then
    echo "
[Unit]
Description=Stubby
After=network-online.target

[Service]
Type=simple
ExecStart=$(which stubby) -l -C /etc/stubby/stubby.yml
Group=internet_out

[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/stubby.service
    systemctl enable stubby.service
    systemctl start stubby.service
else
    stubby -g -C /etc/stubby/stubby.yml
fi

# Make NetworkManager not control DNS
if [ -d /etc/NetworkManager/conf.d ]; then #https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/configuring_and_managing_networking/manually-configuring-the-etc-resolv-conf-file_configuring-and-managing-networking
    echo "[main]
dns=none" > /etc/NetworkManager/conf.d/90-dns-none.conf
    systemctl restart NetworkManager
fi

# If using systemd-resolved, use stubby
if [ -f /etc/systemd/resolved.conf ]; then
    if ! grep -q "DNS=127.0.8.53" /etc/systemd/resolved.conf; then
        echo "DNS=127.0.8.53" >> /etc/systemd/resolved.conf
        systemctl restart systemd-resolved
    fi
fi

if [ -d /etc/resolvconf/resolv.conf.d ]; then
    if ! grep -q "nameserver 127.0.8.53" /etc/resolvconf/resolv.conf.d/head; then
        echo "nameserver 127.0.8.53" >> /etc/resolvconf/resolv.conf.d/head
        resolvconf -u
    fi
fi

if ! grep -q "nameserver 127.0.8.53" /etc/resolv.conf; then
    echo "nameserver 127.0.8.53
$(cat /etc/resolv.conf)" > /etc/resolv.conf
fi

# TODO: On Ubuntu, there's a dns-nameservers line on /etc/network/interfaces & /etc/sysconfig/network

# Grab the DNSSEC Keys
getdns_query -s @127.0.8.53 github.com > /dev/null