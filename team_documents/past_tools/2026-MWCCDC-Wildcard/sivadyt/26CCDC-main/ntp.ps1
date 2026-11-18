Write-Host "Configuring w32time..."
$input = Read-Host -Prompt 'Enter "host" if hosting, press enter for everything else'

if ($input -eq 'host') {
  Write-Host "Hosting NTP Server with w32tm..."
  
  Write-Host "Setting registery values:"

  Write-Host "Enabling NTP Server hosting..."
  Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer" -Name "Enabled" -Value 1
  Write-Host "Done"

  Write-Host "Setting announce flags..."
  Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" -Name "AnnounceFlags" -Value 5
  Write-Host "Done"

  Write-Host "Setting peerlist..."
  w32tm /config /manualpeerlist:"0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org" /syncfromflags:MANUAL /reliable:YES /update
  Write-Host "Done"
} else {
  Write-Host "Setting peerlist..."
  w32tm /config /manualpeerlist:"172.20.242.104" /update
  Write-Host "Done"
}

Write-Host "Restarting service..."
Restart-Service w32time
Write-Host "Done"

Write-Host "Resyncing..."
w32tm /resync /rediscover
w32tm /resync /force
Write-Host "Done"

Write-Host "w32tm setup completed."
Read-Host "Press enter to exit..."
