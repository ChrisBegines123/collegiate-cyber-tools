#!/usr/bin/env bash

echo $SHELL

#BACKUP CONFIGURATION: 
# scp export configuration to sysadmin@172.20.242.30:/tmp/pa-backup.xml from running-config.xml

#==============================================================================
# AUDIT COMMANDS
#==============================================================================
show admins all
show running security-policy
show running nat-policy
show rulebase security rules "Deny-All-Inbound"
show rulebase security rules "Deny-All-Outbound"

# -----------------------------------------------------------------------------------------------------------------------------------------------------
#==============================================================================
# Section 1: Rotate PANOS admin authentication via password rotation
# login: admin
# Password: Changeme123
#==============================================================================

configure 
set mgt-config users admin password <the_greatest_firewall>
commit
# -----------------------------------------------------------------------------------------------------------------------------------------------------
#==============================================================================
# Section 2: Kill rogue accounts and users
### Delete the rogue _cliuser account:
#==============================================================================

configure
set mgt-config users admin password
delete mgt-config users _cliuser
commit


#==============================================================================
# Section 3: Management Interface Lockdown
#==============================================================================


set deviceconfig system permitted-ip 172.20.242.0/24
set deviceconfig system service disable-http yes
set deviceconfig system service disable-telnet yes
set deviceconfig system service disable-snmp yes
commit


#==============================================================================
# Section 4: Deny ALl Security Rules
#==============================================================================
set rulebase security rules "Deny-All-Inbound" from external
set rulebase security rules "Deny-All-Inbound" to any
set rulebase security rules "Deny-All-Inbound" source any
set rulebase security rules "Deny-All-Inbound" destination any
set rulebase security rules "Deny-All-Inbound" application any
set rulebase security rules "Deny-All-Inbound" service any
set rulebase security rules "Deny-All-Inbound" action deny
set rulebase security rules "Deny-All-Inbound" log-start yes
set rulebase security rules "Deny-All-Inbound" log-end yes

set rulebase security rules "Deny-All-Outbound" from internal
set rulebase security rules "Deny-All-Outbound" to external
set rulebase security rules "Deny-All-Outbound" source any
set rulebase security rules "Deny-All-Outbound" destination any
set rulebase security rules "Deny-All-Outbound" application any
set rulebase security rules "Deny-All-Outbound" service any
set rulebase security rules "Deny-All-Outbound" action deny
set rulebase security rules "Deny-All-Outbound" log-start yes
set rulebase security rules "Deny-All-Outbound" log-end yes

move rulebase security rules "Deny-All-Inbound" after "Permit Inbound"
move rulebase security rules "Deny-All-Outbound" after "Deny-All-Inbound"
commit


#==============================================================================
# Section 5: Individual Firewall Rules
# sample command: 
configure
set address BANNED-X ip-netmask X.X.X.X
set rulebase security rules "Block-RedTeam" source BANNED-X
move rulebase security rules "Block-RedTeam" top
commit
#==============================================================================



#==============================================================================
# ON LINUX HOSTS 
#==============================================================================
# iptables -I INPUT -s X.X.X.X -j DROP
# iptables -I INPUT -s Y.Y.Y.Y -j DROP
# service iptables save
