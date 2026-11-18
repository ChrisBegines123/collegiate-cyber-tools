Write-Host "=== Enabling Windows Defender Firewall Logging (No Rule Changes) ==="

$LogPath = "C:\Windows\System32\LogFiles\Firewall\pfirewall.log"

Set-NetFirewallProfile -Profile Domain,Private,Public `
  -LogBlocked True `
  -LogAllowed True `
  -LogFileName $LogPath `
  -LogMaxSizeKilobytes 32767

Write-Host "Firewall logging enabled."
Write-Host "Log file location:"
Write-Host " - $LogPath"
Write-Host ""
Write-Host "Use this command to view recent drops:"
Write-Host " Get-Content $LogPath -Tail 20"
