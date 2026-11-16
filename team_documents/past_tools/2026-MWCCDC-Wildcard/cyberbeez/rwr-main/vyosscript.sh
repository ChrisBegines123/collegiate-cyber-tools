#!/bin/vbash
source /opt/vyatta/etc/functions/script-template
configure
set firewall ipv4 forward filter default-action drop
set firewall ipv4 input filter default-action drop
set firewall ipv4 output filter default-action drop

set firewall ipv6 forward filter default-action drop
set firewall ipv6 input filter default-action drop
set firewall ipv6 output filter default-action drop

set firewall ipv4 forward filter rule 1 action accept
set firewall ipv4 forward filter rule 1 state established
set firewall ipv4 forward filter rule 1 state related

set firewall ipv4 forward filter rule 2 action accept
set firewall ipv4 forward filter rule 2 protocol icmp

set firewall ipv4 forward filter rule 3 action accept
set firewall ipv4 forward filter rule 3 protocol tcp
set firewall ipv4 forward filter rule 3 destination port 80

set firewall ipv4 forward filter rule 4 action accept
set firewall ipv4 forward filter rule 4 protocol tcp
set firewall ipv4 forward filter rule 4 destination port 443

set firewall ipv4 forward filter rule 5 action accept
set firewall ipv4 forward filter rule 5 protocol tcp
set firewall ipv4 forward filter rule 5 destination port 25

set firewall ipv4 forward filter rule 6 action accept
set firewall ipv4 forward filter rule 6 protocol tcp
set firewall ipv4 forward filter rule 6 destination port 110

set firewall ipv4 forward filter rule 7 action accept
set firewall ipv4 forward filter rule 7 protocol tcp
set firewall ipv4 forward filter rule 7 destination port 53

set firewall ipv4 forward filter rule 8 action accept
set firewall ipv4 forward filter rule 8 protocol udp
set firewall ipv4 forward filter rule 8 destination port 53

commit
save

exit
