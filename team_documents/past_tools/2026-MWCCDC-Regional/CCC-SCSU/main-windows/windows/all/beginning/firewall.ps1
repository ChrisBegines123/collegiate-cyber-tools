

New-NetFirewallRule -DisplayName "AD RPC Endpoint Mapper" -Direction Inbound -Protocol TCP -LocalPort 135 -Action Allow -RemoteAddress <trusted_subnet>
New-NetFirewallRule -DisplayName "AD Dynamic RPC" -Direction Inbound -Protocol TCP -LocalPort 49152-65535 -Action Allow -RemoteAddress <trusted_subnet>
New-NetFirewallRule -DisplayName "LDAP" -Direction Inbound -Protocol Any -LocalPort 389 -Action Allow -RemoteAddress <trusted_subnet>
New-NetFirewallRule -DisplayName "LDAP SSL" -Direction Inbound -Protocol TCP -LocalPort 636 -Action Allow -RemoteAddress <trusted_subnet>
New-NetFirewallRule -DisplayName "LDAP GC" -Direction Inbound -Protocol TCP -LocalPort 3268 -Action Allow -RemoteAddress <trusted_subnet>
New-NetFirewallRule -DisplayName "LDAP GC SSL" -Direction Inbound -Protocol TCP -LocalPort 3269 -Action Allow -RemoteAddress <trusted_subnet>
New-NetFirewallRule -DisplayName "DNS" -Direction any -Protocol Any -LocalPort 53 -Action Allow -RemoteAddress <trusted_subnet> 
New-NetFirewallRule -DisplayName "Kerberos" -Direction Inbound -Protocol Any -LocalPort 88 -Action Allow -RemoteAddress <trusted_subnet>
New-NetFirewallRule -DisplayName "Kerberos PW Change" -Direction Inbound -Protocol Any -LocalPort 464 -Action Allow -RemoteAddress <trusted_subnet>
New-NetFirewallRule -DisplayName "SMB for Trusts" -Direction Inbound -Protocol TCP -LocalPort 445 -Action Allow -RemoteAddress <trusted_subnet>
New-NetFirewallRule -DisplayName "FRS RPC" -Direction Inbound -Protocol TCP -LocalPort 49152-65535 -Action Allow -RemoteAddress <trusted_subnet>
New-NetFirewallRule -DisplayName "DFSR RPC" -Direction Inbound -Protocol TCP -LocalPort 49152-65535 -Action Allow -RemoteAddress <trusted_subnet>
New-NetFirewallRule -DisplayName "ADWS" -Direction Inbound -Protocol TCP -LocalPort 9389 -Action Allow -RemoteAddress <trusted_subnet>
New-NetFirewallRule -DisplayName "W32Time" -Direction Outbound -Protocol UDP -LocalPort 123 -Action Allow