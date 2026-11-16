$ipblock = Read-Host "Enter IP address to block"

Write-Host "Blocking"
New-NetFirewallRule -DisplayName "CCDC-Block $ipblock" -Action Block -RemoteAddress $ipblock
New-NetFirewallRule -DisplayName "CCDC-Block $ipblock" -Action Block -RemoteAddress $ipblock -Direction Outbound

Read-Host "Done. Press enter to exit..."
