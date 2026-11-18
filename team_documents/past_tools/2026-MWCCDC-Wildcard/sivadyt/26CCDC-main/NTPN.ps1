function Menu {
  Write-Host "====== Select an option for NTP hosting: ======"
  Write-Host "0 - Cancel"
  Write-Host "1 - Use default newhost (Ecom: 172.20.242.104)"
  Write-Host "2 - Enter newhost IP"
  Write-Host "3 - Host on this machine"
  Write-Host "===============================================`n"
}

Write-Host "Configuring w32time...`n"
do {
  Menu
  $input = Read-Host -Prompt "Enter: "

  switch ($input) {
    "0" { break }
    "1" { 
      Write-Host "`nSetting default newhost..."
      w32tm /config /manualpeerlist:"172.20.242.104" /update
      Write-Host "Done."
    }
    "2" {
      $host = Read-Host -Prompt "Enter newhost IP: "
      w32tm /config /manualpeerlist:"$host" /update
      Write-Host "Done."
    }
    "3" {
      Write-Host "Hosting NTP Server with w32tm..."
      Write-Host "Setting registery values:`n"
      Write-Host "Enabling NTP Server hosting..."
      Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer" -Name "Enabled" -Value 1
      Write-Host "`nDone`n"

      Write-Host "Setting announce flags..."
      Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" -Name "AnnounceFlags" -Value 5
      Write-Host "`nDone`n"

      Write-Host "Setting peerlist..."
      w32tm /config /manualpeerlist:"0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org" /syncfromflags:MANUAL /reliable:YES /update
      Write-Host "`nDone`n"
    } 
  } 
} until ($input -eq "0" -or $input -eq "1" -or $input -eq "2" -or $input -eq "3")

Write-Host "Restarting service..."
Restart-Service w32time
Write-Host "`nDone`n"

Write-Host "Resyncing..."
w32tm /resync /rediscover
w32tm /resync /force
Write-Host "`nDone`n"

Write-Host "w32tm setup completed."
Read-Host "Press enter to exit..."
