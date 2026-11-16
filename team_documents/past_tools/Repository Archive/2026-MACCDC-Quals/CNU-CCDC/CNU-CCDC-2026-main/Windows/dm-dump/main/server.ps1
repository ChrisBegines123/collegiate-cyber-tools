# Administrator
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit }

# GENERAL
function SRV-general() {

    Write-Warning "GENERAL STARTING"
    Write-Host

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name NoLockScreenCamera -Value 1
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name NoLockScreenSlideshow -Value 1

    Write-Host "GENERAL DONE" -ForegroundColor blue -BackgroundColor green
    Write-host

    SRV-start
}

# SMB SERVER
function SRV-smb(){

    Write-Warning "SMB STARTING"
    Write-Host

    # SMB Encryption
    Set-SmbServerConfiguration -EncryptData $true\

    # SMB V1 DISABLE

    Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol
    Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol

    Get-SmbServerConfiguration | Select EnableSMB1Protocol
    Set-SmbServerConfiguration -EnableSMB1Protocol $false

    # SMV V2 & V3
    Get-SmbServerConfiguration | Select EnableSMB2Protocol
    Set-SmbServerConfiguration -EnableSMB2Protocol $false

    sc.exe config lanmanworkstation depend= bowser/mrxsmb10/mrxsmb20/nsi
    sc.exe config mrxsmb20 start= auto

    Write-Host "SMB DONE" -ForegroundColor blue -BackgroundColor green
    Write-host

    SRV-start

}



# RDP SERVER
function SRV-rdp() {

    Write-Warning "RDP STARTING"
    Write-Host

    # Enable RDP
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -value 0

    # Allow RDP through Firewall
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

    Write-Host "RDP DONE" -ForegroundColor blue -BackgroundColor green
    Write-host

    SRV-start
}

function SRV-www(){

    Write-Warning "WWW STARTING"
    Write-Host
    
    Write-Host "WWW DONE" -ForegroundColor blue -BackgroundColor green
    Write-host

    SRV-start
}

function SRV-ftp(){
    
    Write-Warning "FTP STARTING"
    Write-Host

    Write-Host "FTP DONE" -ForegroundColor blue -BackgroundColor green
    Write-host

    SRV-start
}

function SRV-iis(){
    
    Write-Warning "IIS STARTING"
    Write-Host

    Write-Host "IIS DONE" -ForegroundColor blue -BackgroundColor green
    Write-host

    SRV-start
}

function SRV-adds(){
    
    Write-Warning "ADDS STARTING"
    Write-Host

    import-module Active Directory

    $password = ConvertTo-SecureString "Cyb3rPatr1ot!@" -AsPlainText -Force

    Get-ADUser -Filter *

    $users = Get-ADuser
    Set-ADAccountPassword

    Write-Host "ADDS DONE" -ForegroundColor blue -BackgroundColor green
    Write-host

    SRV-start
}

function SRV-sql(){
    
    Write-Warning "SQL STARTING"
    Write-Host

    Write-Host "SQL DONE" -ForegroundColor blue -BackgroundColor green
    Write-host

    SRV-start
}

function SRV-azure(){
    
    Write-Warning "AZURE STARTING"
    Write-Host

    Write-Host "AZURE DONE" -ForegroundColor blue -BackgroundColor green
    Write-host

    SRV-start
}

function SRV-start() {

    Write-Host
    Write-Host "Enter a number to choose an option"
    Write-Host "1 : General Server stuff (DO THIS FIRST)"
    Write-Host "Automated Tasks (READ SERVER CRITICAL SERVICES FOR MANUAL TASKS):"
    Write-Host "2 : SMB"
    Write-Host "3 : RDP"
    Write-Host "4 : WWW"
    Write-Host "5 : FTP"
    Write-Host "6 : IIS"
    Write-Host "7 : ADDS"
    Write-Host "8 : SQL"
    Write-Host "9 : Azure"

    [int]$p = Read-Host

    $result = switch ($p) {
        1 { SRV-general }
        2 { SRV-smb } 
        3 { SRV-rdp }
        4 { SRV-www }
        5 { SRV-ftp }
        6 { SRV-iis }
        7 { SRV-adds }
        8 { SRV-sql }
        9 { SRV-azure }
    } 

    $result

}

SRV-start