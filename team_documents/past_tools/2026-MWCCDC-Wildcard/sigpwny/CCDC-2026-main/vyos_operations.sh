#! /usr/bin/vbash

# Block everything, then slowly deploy and reopen ports and services for what is needed. 
# BELOW: COMMAND REFERENCE

#==============================================================================
# Section X: Ban individual INBOUND IPs on VyOS
# configure
# set firewall ipv4 forward filter rule XX action drop
# set firewall ipv4 forward filter rule XX source address X.X.X.X
# set firewall ipv4 forward filter rule XX inbound-interface name eth0
# commit
# save
#==============================================================================
~
#==============================================================================
# Section X: Ban OUTBOUND IPs on VyOS
# configure
# set firewall group network-group BLOCKED-C2 network X.X.X.X/32
# commit
# save
#==============================================================================



# -----------------------------------------------------------------------------------------------------------------------------------------------------
#==============================================================================
# EMERGENCY ROLLBACK
#==============================================================================
#
# If ALL scoring breaks:
#   configure
#   delete firewall interface eth0 forward
#   delete firewall interface eth0 out
#   commit
#
# If ONE service breaks — add a rule:
#   configure
#   set firewall ipv4 name TRANSIT-FILTER rule XXXX action accept
#   set firewall ipv4 name TRANSIT-FILTER rule XXXX protocol tcp
#   set firewall ipv4 name TRANSIT-FILTER rule XXXX destination address <PUBLIC-IP>
#   set firewall ipv4 name TRANSIT-FILTER rule XXXX destination port <PORT>
#   commit
#
# To add more C2 IPs:
#   configure
#   set firewall group network-group BLOCKED-C2 network X.X.X.X/32
#   commit
#   save
# -----------------------------------------------------------------------------------------------------------------------------------------------------

# -----------------------------------------------------------------------------------------------------------------------------------------------------
#==============================================================================
# FULL RULE MAP (for quick reference when adding rules on the fly)
#==============================================================================
#
# ROUTER-PROTECT (eth0 input):
#   20   established/related
#   40   drop invalid
#   60   ICMP
#   80   SSH from INTERNAL
#   100  DNS from INTERNAL
#   120  NTP
#   ---  default DROP
#
# TRANSIT-FILTER (eth0 forward):
#   20   established/related
#   40   drop invalid
#   60   drop C2
#   80   ICMP
#   ---- inbound scored services ----
#   1000 Ecom HTTP/HTTPS           → 172.25.23.11:80,443
#   1020 Webmail SMTP/POP3/IMAP    → 172.25.23.39:25,110,143,587,993,995
#   1040 Splunk HTTP/HTTPS         → 172.25.23.9:80,443,8000,8443
#   1060 (available)
#   1080 AD/DNS TCP                → 172.25.23.155:53
#   1100 AD/DNS UDP                → 172.25.23.155:53
#   1120 Web Server HTTP/HTTPS     → 172.25.23.140:80,443
#   1140 FTP Server                → 172.25.23.162:20,21,990,1024-65535
#   1160 (available)
#   1180 (available)
#   ---- outbound from servers ----
#   2000 DNS UDP out
#   2020 DNS TCP out
#   2040 HTTP/HTTPS out
#   2060 NTP out
#   2080 SMTP out (webmail only)
#   2100 (available)
#   ---- inter-segment ----
#   3000 PA → FTD
#   3020 FTD → PA
#   3040 (available)
#   ---  default DROP
#
# OUTBOUND-FILTER (eth0 out):
#   20   established/related
#   40   drop C2
#   60   ICMP
#   200  DNS
#   220  HTTP/HTTPS
#   240  NTP
#   260  SMTP
#   280  (available)
#   ---  default DROP
#
# --------------------------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------------------------------------------------------------------
#==============================================================================
# VERIFICATION COMMANDS
#==============================================================================
#
# show system login
# show protocols static route
# show nat source rules
# show service ssh
# show service dns forwarding
# show firewall
# show firewall statistics
# show system syslog
# show log firewall name TRANSIT-FILTER
# show conntrack table | head 30
# -----------------------------------------------------------------------------------------------------------------------------------------------------

# -----------------------------------------------------------------------------------------------------------------------------------------------------
#==============================================================================
# Section 1: Rotate vyos admin authentication via password rotation
#==============================================================================
configure
set system login user vyos authentication plaintext-password "MY-PASSWORD" 
commit 
save
# -----------------------------------------------------------------------------------------------------------------------------------------------------

# Exit configuraiton mode and return to operational mode
# -----------------------------------------------------------------------------------------------------------------------------------------------------

# -----------------------------------------------------------------------------------------------------------------------------------------------------
# ==============================================================================
# Section 2
# Delete rogue users from the box. Using only known red team name from previous experience. 
# ==============================================================================
# -----------------------------------------------------------------------------------------------------------------------------------------------------
delete system login user cliuser_ 2>/dev/null
commit
save


# -----------------------------------------------------------------------------------------------------------------------------------------------------
#==============================================================================
# Section 3: Fix DNS Forwarding 
#==============================================================================
# -----------------------------------------------------------------------------------------------------------------------------------------------------
delete service dns forwarding name-server 192.168.10.53 2>/dev/null
set service dns forwarding name-server 8.8.8.8
set service dns forwarding name-server 8.8.4.4
commit
save

# -----------------------------------------------------------------------------------------------------------------------------------------------------
#==============================================================================
# Section 4: HARDEN SSH, restrict to internal but do not delete service 
#==============================================================================

set service ssh listen-address 172.16.101.1
set service ssh listen-address 172.16.102.1
set service ssh port 22
delete service telnet 2>/dev/null
delete service http 2>/dev/null
commit
save
# -----------------------------------------------------------------------------------------------------------------------------------------------------

#==============================================================================
# Section 5: Known Malicious IPs
# Known C2 IPs from qualifier
#==============================================================================
set firewall group network-group BLOCKED-C2 network 10.0.9.7
set firewall group network-group BLOCKED-C2 network 10.96.2.205
set firewall group network-group BLOCKED-C2 network 10.176.7.166

# -----------------------------------------------------------------------------------------------------------------------------------------------------
#==============================================================================
# Section 6: Reduce abuse of connection tracking helpers. Attackers leverage ports opening other ports in certain circumstances. 
#==============================================================================
delete system conntrack modules h323 2>/dev/null
delete system conntrack modules pptp 2>/dev/null
delete system conntrack modules sip 2>/dev/null
delete system conntrack modules sqlnet 2>/dev/null
delete system conntrack modules tftp 2>/dev/null
commit
save

# -----------------------------------------------------------------------------------------------------------------------------------------------------
#==============================================================================
# Section 7: Configure syslog to Splunk, providing centralized logging. 
#==============================================================================
set system syslog host 172.20.242.20 facility all level info
set system syslog host 172.20.242.20 port 514
set system syslog host 172.20.242.20 protocol udp
commit
save
# -----------------------------------------------------------------------------------------------------------------------------------------------------

#==============================================================================
# Section 8: Define groups prior to firewall rules 
#==============================================================================

set firewall group network-group INTERNAL network 172.16.101.0/24
set firewall group network-group INTERNAL network 172.16.102.0/24
set firewall group network-group INTERNAL network 172.20.240.0/24
set firewall group network-group INTERNAL network 172.20.242.0/24

set firewall group network-group BLOCK_IP address 10.0.9.7
set firewall group network-group BLOCK_IP address 10.96.2.205
set firewall group network-group BLOCK_IP address 10.176.7.166

commit
save

# -----------------------------------------------------------------------------------------------------------------------------------------------------

#==============================================================================
# Section 9: Firewall rules (lowest labeled #s are prioritized highest)
#==============================================================================

