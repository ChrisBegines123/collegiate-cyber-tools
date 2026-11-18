# ==============================================================================
# Script Name : .\win_server_hardening.ps1
# Description : Hardens Windows Server security settings.
# Version     : 1.0
# ==============================================================================
# Usage       : .\win_server_hardening.ps1
# Nptes       : 
#  - Designed for the 2024 MWCCDC competition environment.
# ==============================================================================


# Ensure the script runs with administrative privileges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Run this script as an administrator."
    exit
}

function Export-CommandHistory {
    $historyFile = (Get-PSReadlineOption).HistorySavePath
    if (Test-Path $historyFile) {
        $outputPath = "$env:USERPROFILE\Documents\CommandHistory.txt"
        Get-Content $historyFile | Out-File -FilePath $outputPath -Encoding UTF8
        Write-Host "Command history exported to $outputPath"
    } else {
        Write-Host "No command history file found."
    }
}

function Set-RestrictedExecutionPolicy {
    Set-ExecutionPolicy -ExecutionPolicy Restricted -Force
    Write-Host "Execution policy set to Restricted."
}

function Disable-Remoting {
    Disable-PSRemoting -Force -SkipNetworkProfileCheck
    Write-Host "WinRM Disabled"
    # Disable RDP
    try {
        # Set registry value to deny Remote Desktop connections
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 1 -Force

        # Optionally disable the Remote Desktop Service (TermService)
        Set-Service -Name TermService -StartupType Disabled -ErrorAction SilentlyContinue
        Stop-Service -Name TermService -Force -ErrorAction SilentlyContinue
        Write-Host "Remote Desktop has been disabled." -ForegroundColor Green

        # Configure Audit Policies for Domain Controller
        auditpol /set /category:"Account Logon" /success:enable /failure:enable
        auditpol /set /category:"Logon/Logoff" /success:enable /failure:enable
        auditpol /set /category:"Account Management" /success:enable /failure:enable
        auditpol /set /category:"Object Access" /success:enable /failure:enable
        auditpol /set /category:"Policy Change" /success:enable /failure:enable
    }
    catch {
        Write-Host "error in disabling remote assistance: $_" -ForegroundColor Red
    }
    # Disable remote registry
    try {
        Set-Service -Name RemoteRegistry -StartupType Disabled -ErrorAction SilentlyContinue
        Stop-Service -Name RemoteRegistry -Force -ErrorAction SilentlyContinue
        Write-Host "Remote Registry service has been disabled." -ForegroundColor Green
    }
    catch {
        Write-Host "Error disabling Remote Registry: $_" -ForegroundColor Red
    }
}

function Stop-UnnecessaryServices {
    $services = @("bthserv", "MapsBroker", "Spooler", "SSDPSRV")
    foreach ($service in $services) {
        if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
            Stop-Service -Name $service -Force
            Write-Host "Stopped service: $service"
        } else {
            Write-Host "Service not found: $service"
        }
    }
}

function Check-LastLogon {
    $adminLastLogon = (net user administrator | Select-String -Pattern "^Last logon").Line
    Write-Host "Administrator's last logon: $adminLastLogon"
}

Function Disable-SMBv1 {
    Write-Host "Disabling SMBv1..."
    Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart
}

# Configure firewall rules
function Invoke-NetworkHardening {
    try {
        Write-SecurityLog "Configuring Advanced Windows Firewall for AD DNS Server"
        
        # Disable all inbound connections by default
        netsh advfirewall set allprofiles firewallpolicy blockinbound,blockoutbound

        # Essential ports for Active Directory and DNS
        $criticalAllowedPorts = @(
            # DNS Ports
            @{Port=53; Protocol="TCP"; Name="DNS-TCP"},
            @{Port=53; Protocol="UDP"; Name="DNS-UDP"},
            
            # Active Directory Communication Ports
            @{Port=88; Protocol="TCP"; Name="Kerberos"},    # Kerberos Authentication
            @{Port=88; Protocol="UDP"; Name="Kerberos-UDP"},
            @{Port=389; Protocol="TCP"; Name="LDAP"},       # Lightweight Directory Access Protocol
            @{Port=636; Protocol="TCP"; Name="LDAPS"},      # LDAP over SSL
            @{Port=464; Protocol="TCP"; Name="Kpasswd"},    # Kerberos password change
            @{Port=464; Protocol="UDP"; Name="Kpasswd-UDP"},
            
            # Domain Controller Communication
            @{Port=3268; Protocol="TCP"; Name="Global-Catalog"},  # Global Catalog
            @{Port=3269; Protocol="TCP"; Name="Global-Catalog-SSL"},
            
            # RPC for AD Replication
            @{Port=135; Protocol="TCP"; Name="RPC-Endpoint-Mapper"},
            @{Port=49152; Protocol="TCP"; Name="RPC-Dynamic-Ports-Low"},
            @{Port=49153; Protocol="TCP"; Name="RPC-Dynamic-Ports-Mid"},
            @{Port=49154; Protocol="TCP"; Name="RPC-Dynamic-Ports-High"}
        )

        # Add firewall rules for critical AD and DNS ports
        foreach ($rule in $criticalAllowedPorts) {
            netsh advfirewall firewall add rule `
                name="Allow-${$rule.Name}" `
                dir=in `
                action=allow `
                protocol=$rule.Protocol `
                localport=$rule.Port `
                profile=domain,private `
                enable=yes
        }

        # Block common attack ports
        $blockedPorts = @(
            21,   # FTP
            22,   # SSH
            23,   # Telnet
            25,   # SMTP
            110,  # POP3
            143,  # IMAP
            445,  # SMB
            #3389  # RDP
        )
        foreach ($port in $blockedPorts) {
            netsh advfirewall firewall add rule `
                name="Block-Port-$port" `
                dir=in `
                action=block `
                protocol=TCP `
                localport=$port
        }

        Write-SecurityLog "AD Network Hardening Complete" -Success
    }
    catch {
        Write-SecurityLog "Network Hardening Failed: $_" -Error
    }
}

#Function Disable-UnnecessaryAccounts {
#    Write-Host "Disabling unnecessary user accounts..."
#    Get-LocalUser | Where-Object { $_.Enabled -eq $true -and $_.Name -notmatch "Administrator|DefaultAccount|Guest" } | ForEach-Object {
#        Disable-LocalUser -Name $_.Name
 #       Write-Host "Disabled account: $_.Name"
#    }
#}

Function Configure-NTP {
    Write-Host "Configuring NTP..."
    w32tm /config /manualpeerlist:"pool.ntp.org" /syncfromflags:manual /reliable:YES /update
    Restart-Service w32time
    w32tm /resync
}

function Check-HostsFile {
    $hostsFilePath = "$env:WinDir\System32\drivers\etc\hosts"
    if (Test-Path $hostsFilePath) {
        Write-Host "Opening hosts file for review..."
        notepad.exe $hostsFilePath
    } else {
        Write-Host "Hosts file not found."
    }
}

function Get-ADUserLastLogon {
    if (Get-Command Get-ADUser -ErrorAction SilentlyContinue) {
        Get-ADUser -Filter * -Properties LastLogonDate | 
            Select-Object Name, LastLogonDate | 
            Format-Table -AutoSize
    } else {
        Write-Host "Active Directory module not installed or available."
    }
}

Function Install-WLANService {
    Write-Host "Installing Wireless LAN Service..."
    Add-WindowsFeature -Name Wireless-Networking
    Start-Service -Name "WlanSvc"
}

#Function Download-Splunk {
#    Write-Host "Downloading Splunk Universal Forwarder..."
 #   $url = "https://download.splunk.com/products/universalforwarder/releases/9.2.0.1/windows/splunkforwarder-9.2.0.1-d8ae995bf219-x64-release.msi"
 #   $output = "C:\SplunkForwarder.msi"
 #   Invoke-WebRequest -Uri $url -OutFile $output
#    Write-Host "Splunk downloaded to $output"
#}


# Main script execution
Write-Host "Starting server configuration script..."


Disable-SMBv1

Invoke-NetworkHardening

#Disable-UnnecessaryAccounts

Configure-NTP

#Set-RestrictedExecutionPolicy

#Install-WLANService

#Download-Splunk

Stop-UnnecessaryServices

Disable-Remoting

Check-HostsFile

Check-LastLogon

Get-ADUserLastLogon

Export-CommandHistory


Write-Host "Script execution completed."
