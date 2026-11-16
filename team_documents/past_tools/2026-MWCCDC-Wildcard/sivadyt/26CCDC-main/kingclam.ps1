$clamurl = "https://github.com/Cisco-Talos/clamav/releases/download/clamav-1.5.1/clamav-1.5.1.win.x64.msi"
$giturl = "https://raw.githubusercontent.com/sivadyt/ChainsawMan/refs/heads/main/clamd.conf"
$giturl2 = "https://raw.githubusercontent.com/sivadyt/ChainsawMan/refs/heads/main/freshclam.conf"

Write-Host "Downloading and installing ClamAV..."
msiexec /i "https://github.com/Cisco-Talos/clamav/releases/download/clamav-1.5.1/clamav-1.5.1.win.x64.msi" /qn
Sleep 10
Write-Host "Done"

Write-Host "Downloading configuration files..."
Invoke-WebRequest -Uri $giturl -OutFile "C:\Program Files\ClamAV\clamd.conf"
Invoke-WebRequest -Uri $giturl2 -OutFile "C:\Program Files\ClamAV\freshclam.conf"
Write-Host "Done"

Write-Host "ClamAV installed..."
Write-Host "Remember to update database with freshclam"
Write-Host 'Scan with clamscan "\folderpath"'
Read-Host "Press Enter to finish...."
