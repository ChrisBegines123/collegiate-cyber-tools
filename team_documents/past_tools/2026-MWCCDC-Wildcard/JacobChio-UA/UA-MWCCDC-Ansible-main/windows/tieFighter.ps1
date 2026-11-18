curl.exe -O 'https://www.openinfosecfoundation.org/download/windows/Suricata-8.0.3-windivert-1-64bit.msi'
Start-Process msiexec.exe -Wait -ArgumentList '/I Suricata-8.0.3-windivert-1-64bit.msi /qn'
(Invoke-WebRequest 'https://rules.emergingthreats.net/open/suricata-8.0.3/rules/' -UseBasicParsing).Links | Where-Object -Property href -match '.rules' | ForEach-Object{
    curl.exe --output "C:\Program Files\Suricata\rules\$($_.href.substring(2))" "https://rules.emergingthreats.net/open/suricata-8.0.3/rules$($_.href.substring(1))" 
    write-host "https://rules.emergingthreats.net/open/suricata-8.0.3/rules$($_.href.substring(1))"
}
start-process 'C:\Program Files\Suricata\suricata.exe' -Wait -ArgumentList "-i $($(Get-NetIPAddress | Where-Object -Property ipaddress -match '172.*.*.*').ipaddress) --service-install"