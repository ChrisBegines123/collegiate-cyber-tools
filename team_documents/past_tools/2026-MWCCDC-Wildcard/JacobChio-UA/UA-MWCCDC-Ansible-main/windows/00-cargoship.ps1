Save-Script -name winget-install -path .\ -force
winget-install.ps1
Stop-Process -Name explorer -Force
winget.exe install cURL.cURL -e --accept-source-agreements --accept-package-agreements
curl.exe -OL 'https://download.sysinternals.com/files/SysinternalsSuite.zip'
curl.exe -OL 'https://npcap.com/dist/npcap-1.87.exe'
Start-Process -FilePath 'npcap-1.87.exe' -Wait
Expand-Archive -Path SysinternalsSuite.zip -DestinationPath C:\SysinternalsSuite\ -Force
winget.exe install WiresharkFoundation.Wireshark -e --accept-source-agreements --accept-package-agreements
winget.exe install Insecure.Nmap -e --accept-source-agreements --accept-package-agreements
winget.exe install Microsoft.PowerShell -e --accept-source-agreements --accept-package-agreements
winget.exe install Microsoft.VisualStudioCode -e --accept-source-agreements --accept-package-agreements
winget.exe install Microsoft.WindowsTerminal -e --accept-source-agreements --accept-package-agreements
winget.exe install Microsoft.etl2pcapng -e --accept-source-agreements --accept-package-agreements
winget.exe install Git.Git -e --accept-source-agreements --accept-package-agreements
