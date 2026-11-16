#!/usr/bin/env bash
# Description:
# Setups sample firewall rules
# Usage:
# ./<SCRIPT NAME>
# Supports ICMP, and user defined rules in vars input_rules and output_rules

# Variables
Inside="172.20.240.0/22"
Any="0.0.0.0/0"

input_rules=(
#    "21 tcp $Any honeypot_in" # Telnet/FTP from any
#    "23 tcp $Any honeypot_in" # Telnet/FTP from any
#    "22 tcp $Any ssh_in" # SSH from any
    "25 tcp $Any all" # SMTP from any
    "53 udp $Any dns_in" # DNS from any
#    "69 udp $Any all" # TFTP from any
    "80 tcp $Any http_in" # HTTP from any
    "110 tcp $Any mail_in" # POP3 from any
    "123 udp $Inside ntp_in" # NTP from inside
    "143 tcp $Any mail_in" # IMAP from any
#    "514 udp $Inside all" # Syslog from inside (UDP)
#    "514 tcp $Inside all" # Syslog from inside (TCP)
#    "3306 tcp $Inside all" # MySQL from inside
    "8000 tcp $Any all" # Splunk from any
)

output_rules=(
    "80 tcp $Any internet_out" # HTTP to any
    "53 udp $Any internet_out" # DNS to AD
    "53 udp 172.20.242.200 internet_out" # DNS to AD
    "123 udp 172.20.240.20 all" # NTP to Debian 8.5
#    "389 tcp 172.20.242.200" # LDAP to AD
    "443 tcp $Any internet_out" # HTTPS to any
    "443 tcp 172.20.242.150 all" # HTTPS to Palo Alto
    "514 udp 172.20.241.20 root" # Syslog to Splunk
#    "3306 tcp 172.20.242.10" # MySQL to Web
    "1514 tcp 172.20.241.20 all" # Wazuh Agent Connection
    "1515 tcp 172.20.241.20 all" # Wazuh Agent Enrollment
    "1516 tcp 172.20.241.20 all" # Wazuh Agent Cluster
    "8000 tcp 172.20.241.20 internet_out" # HTTP to Splunk
)

. $(dirname "$0")/helper.sh; if [ -z ${PUBLIC_KEY+x} ]; then exit 1; fi
root_check

if [ -f "/usr/sbin/iptables-nft" ]; then # Oh no
    shopt -s expand_aliases
    alias iptables=/usr/sbin/iptables-nft
    alias iptables-save=/usr/sbin/iptables-nft-save
    alias ip6tables=/usr/sbin/ip6tables-nft
    alias ip6tables-save=/usr/sbin/ip6tables-nft-save
fi

# Reset and disable IPv6
table_names=$(ip6tables-save | grep '^*' | sed 's/*//g' | sort | uniq)
for table_name in $table_names
do
  ip6tables -t $table_name -F
  ip6tables -t $table_name -X
done
ip6tables -F
ip6tables -X
ip6tables -Z
ip6tables -P INPUT DROP
ip6tables -P OUTPUT DROP
ip6tables -P FORWARD DROP

# Reset IPv4
table_names=$(iptables-save | grep '^*' | sed 's/*//g' | sort | uniq)
for table_name in $table_names
do
  iptables -t $table_name -F
  iptables -t $table_name -X
done
iptables -F
iptables -X
iptables -Z
iptables -P FORWARD DROP

# IPv4 inbound
iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
iptables -A INPUT -f -j DROP
iptables -A INPUT -p icmp --icmp-type echo-reply -m length --length 40:84 -m state --state NEW,ESTABLISHED,RELATED -m hashlimit --hashlimit-name PING_IREP --hashlimit 1/sec --hashlimit-burst 3 --hashlimit-mode srcip --hashlimit-htable-expire 300000 -j ACCEPT
iptables -A INPUT -p icmp --icmp-type echo-request -m length --length 40:84 -m state --state NEW,ESTABLISHED,RELATED -m hashlimit --hashlimit-name PING_IREQ --hashlimit 1/sec --hashlimit-burst 3 --hashlimit-mode srcip --hashlimit-htable-expire 300000 -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
for i in "${input_rules[@]}"; do
    IFS=' ' read -ra rule <<< "$i"
    if [[ ${rule[3]} == "all" ]]; then
        iptables -A OUTPUT -p "${rule[1]}" --dport "${rule[0]}" -s "${rule[2]}" -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
    else
        iptables -A OUTPUT -p "${rule[1]}" --dport "${rule[0]}" -s "${rule[2]}" -m owner --gid-owner "${rule[3]}" -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
    fi
done
iptables -P INPUT DROP

# IPv4 outbound
iptables -A OUTPUT -p icmp --icmp-type echo-reply -m length --length 40:84 -m state --state NEW,ESTABLISHED,RELATED -m hashlimit --hashlimit-name PING_OREP --hashlimit 1/sec --hashlimit-burst 3 --hashlimit-mode srcip --hashlimit-htable-expire 300000 -j ACCEPT
iptables -A OUTPUT -p icmp --icmp-type echo-request -m length --length 40:84 -m state --state NEW,ESTABLISHED,RELATED -m hashlimit --hashlimit-name PING_OREQ --hashlimit 1/sec --hashlimit-burst 3 --hashlimit-mode srcip --hashlimit-htable-expire 300000 -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -o lo -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
for i in "${output_rules[@]}"; do
    IFS=' ' read -ra rule <<< "$i"
    if [[ ${rule[3]} == "all" ]]; then
        iptables -A OUTPUT -p "${rule[1]}" --dport "${rule[0]}" -d "${rule[2]}" -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
    else
        iptables -A OUTPUT -p "${rule[1]}" --dport "${rule[0]}" -d "${rule[2]}" -m owner --gid-owner "${rule[3]}" -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
    fi
done
iptables -P OUTPUT DROP

if [ -f "/etc/iptables/rules.v4" ]; then
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
fi

if [ -d "/etc/sysconfig" ]; then
    iptables-save > /etc/sysconfig/iptables
    ip6tables-save > /etc/sysconfig/ip6tables
    if [ -f "/etc/sysconfig/iptables" ] && ! systemctl list-unit-files --type=service | grep -q "\<iptables.service\>"; then
        web yum install iptables-services -y
        systemctl enable iptables.service
    fi
fi

#if [ -f "/usr/sbin/iptables-restore-translate" ]; then
#    iptables-save > tmp.iptables
#    iptables-restore-translate -f tmp.iptables > tmp.nft
#    nft -f tmp.nft
#fi

if [ ! -f "/etc/iptables/rules.v4" ] && command -v apt-get >/dev/null 2>&1; then
    web apt-get update
    web apt-get install -y iptables-persistent
fi

# TODO: Proper nftables