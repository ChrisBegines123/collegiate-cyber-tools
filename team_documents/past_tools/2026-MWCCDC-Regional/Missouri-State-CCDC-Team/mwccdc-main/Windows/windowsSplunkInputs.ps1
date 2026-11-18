<#
.SYNOPSIS
    Deploys a role-specific inputs.conf to a Windows Server
    (Active Directory/DNS, Web, or FTP) for Splunk Universal Forwarder.
#>

# Location of inputs.conf
$inputsPath = "C:\Program Files\SplunkUniversalForwarder\etc\system\local\inputs.conf"

Write-Host "Select the server role to configure for Splunk forwarding:`n"
Write-Host "1. Active Directory / DNS (2019)"
Write-Host "2. Web Server (2019)"
Write-Host "3. FTP Server (2022)"
$choice = Read-Host "Enter the number (1-3)"

switch ($choice) {
    1 {
        $content = @"
[default]
host = AD-DNS-2019

[WinEventLog://Security]
disabled = 0
index = winevent_security

[WinEventLog://System]
disabled = 0
index = winevent_system

[WinEventLog://Application]
disabled = 0
index = winevent_application

[WinEventLog://Directory Service]
disabled = 0
index = winevent_ad

[WinEventLog://DNS Server]
disabled = 0
index = winevent_dns

[WinEventLog://PowerShell]
disabled = 0
index = winevent_powershell

[WinEventLog://Microsoft-Windows-Sysmon/Operational]
disabled = 0
index = winevent_sysmon
"@
        $role = "Active Directory / DNS 2019"
    }

    2 {
        $content = @"
[default]
host = WEB-2019

[WinEventLog://Security]
disabled = 0
index = winevent_security

[WinEventLog://System]
disabled = 0
index = winevent_system

[WinEventLog://Application]
disabled = 0
index = winevent_application

[monitor://C:\inetpub\logs\LogFiles\W3SVC1]
disabled = 0
sourcetype = iis
index = web_logs
whitelist = \.log$

[monitor://C:\Windows\System32\LogFiles\HTTPERR]
disabled = 0
sourcetype = httperr
index = web_logs
whitelist = \.log$
"@
        $role = "Web Server 2019"
    }

    3 {
        $content = @"
[default]
host = FTP-2022

[WinEventLog://Security]
disabled = 0
index = winevent_security

[WinEventLog://System]
disabled = 0
index = winevent_system

[WinEventLog://Application]
disabled = 0
index = winevent_application

[monitor://C:\inetpub\logs\LogFiles\FTPSVC1]
disabled = 0
sourcetype = iis:ftp
index = ftp_logs
whitelist = \.log$
"@
        $role = "FTP Server 2022"
    }

    default {
        Write-Host "Invalid selection. Exiting." -ForegroundColor Red
        exit
    }
}

# Create backup if file exists
if (Test-Path $inputsPath) {
    $backup = "$inputsPath.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item $inputsPath $backup -Force
    Write-Host "Existing inputs.conf backed up to: $backup" -ForegroundColor Yellow
}

# Write new configuration
Set-Content -Path $inputsPath -Value $content -Encoding UTF8
Write-Host "✅ inputs.conf deployed for $role"
Write-Host "File written to: $inputsPath"
