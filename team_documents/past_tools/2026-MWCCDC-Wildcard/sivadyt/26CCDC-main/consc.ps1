# Requires -RunAsAdministrator
# FTP Server Hardening (CCDC)
# Defensive hardening: base OS + firewall + logging + (optional) IIS/FTP knobs
# Safe defaults: only touches common risky services + policies.
# Adjust: $FtpControlPort, $PassivePortRange, $AdminMgmtCIDRs

$ErrorActionPreference = "Stop"

# --- EDIT ME ---
$AdminMgmtCIDRs    = @("172.20.240.0/24")  # admin VLAN(s) allowed for RDP/management
$AllowRdp          = $false              # set $false to fully disable RDP inbound
$EnableFtpsOnly    = $false              # requires IIS FTP configured for SSL
$DisableWinRM       = $true             # set $false if you need WinRM
$DisableSMBv1       = $true
$DisableLLMNR       = $true
$DisableNetBIOS     = $true
# --------------

function Disable-ServiceSafe($name) {
  $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
  if ($svc) {
    if ($svc.Status -ne "Stopped") { Stop-Service -Name $name -Force -ErrorAction SilentlyContinue }
    Set-Service -Name $name -StartupType Disabled -ErrorAction SilentlyContinue
    Write-Host "[OK] Disabled service: $name"
  } else {
    Write-Host "[..] Service not present: $name"
  }
}

function Set-RegDword($path, $name, $value) {
  New-Item -Path $path -Force | Out-Null
  New-ItemProperty -Path $path -Name $name -PropertyType DWord -Value $value -Force | Out-Null
}

Write-Host "=== FTP Server hardening (Windows) ==="

# --- Kill common lateral-move / attack surface services ---
Disable-ServiceSafe "Spooler"           # Print Spooler
Disable-ServiceSafe "RemoteRegistry"
Disable-ServiceSafe "Fax"
Disable-ServiceSafe "BluetoothSupportService"
Disable-ServiceSafe "WSearch"           # Windows Search (optional, but common)
Disable-ServiceSafe "CscService"        # Offline Files
Disable-ServiceSafe "WerSvc"            # Windows Error Reporting (optional)
([WmiClass]'Win32_OfflineFilesCache').Enable($false) # Disable Offline Files Caching

if ($DisableWinRM) {
  Disable-ServiceSafe "WinRM"
}

# --- SMBv1 OFF ---
if ($DisableSMBv1) {
  Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue | Out-Null
  Write-Host "[OK] SMBv1 disabled (feature)."
}

# --- LLMNR OFF ---
if ($DisableLLMNR) {
  Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" "EnableMulticast" 0
  Write-Host "[OK] LLMNR disabled (policy registry)."
}

# --- NetBIOS over TCP/IP OFF (all NICs) ---
if ($DisableNetBIOS) {
  Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled=TRUE" |
    ForEach-Object {
      try {
        $_.SetTcpipNetbios(2) | Out-Null  # 2 = Disable NetBIOS
        Write-Host "[OK] NetBIOS disabled on: $($_.Description)"
      } catch {
        Write-Host "[!!] NetBIOS disable failed on: $($_.Description) -> $($_.Exception.Message)"
      }
    }
}

# --- PowerShell logging (good CCDC visibility) ---
Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" "EnableScriptBlockLogging" 1
Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging" "EnableModuleLogging" 1
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames" -Force | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames" -Name "*" -PropertyType String -Value "*" -Force | Out-Null
Write-Host "[OK] PowerShell ScriptBlock + Module logging enabled."

# --- Advanced auditing (minimum useful set) ---
auditpol /set /category:"Logon/Logoff" /success:enable /failure:enable | Out-Null
auditpol /set /category:"Account Logon" /success:enable /failure:enable | Out-Null
auditpol /set /category:"Account Management" /success:enable /failure:enable | Out-Null
auditpol /set /category:"Policy Change" /success:enable /failure:enable | Out-Null
auditpol /set /subcategory:"Process Creation" /success:enable /failure:disable | Out-Null
Write-Host "[OK] Audit policy enabled (logon/account/policy/process creation)."

# --- Windows Firewall: default deny inbound, then allow only what you need ---
# Ensure firewall is enabled
netsh advfirewall set allprofiles state on | Out-Null
Write-Host "[OK] Firewall enabled (all profiles)."

# Block inbound and outbound by default
netsh advfirewall set allprofiles firewallpolicy blockinbound,blockoutbound | Out-Null
Write-Host "[OK] Firewall policy set: block inbound / block outbound."

# Disable default inbound firewall rules
Get-NetFirewallRule -Direction Inbound -ErrorAction SilentlyContinue | Disable-NetFirewallRule -ErrorAction SilentlyContinue

# --- Allow FTP control + passive ports (TCP) ---
Set-NetFirewallRule -DisplayName "FTP Server (FTP Traffic-In)" -Enabled True
Set-NetFirewallRule -DisplayName "FTP Server Passive (FTP Passive Traffic-In)" -Enabled True
Set-NetFirewallRule -DisplayName "FTP Server Secure (FTP SSL Traffic-In)" -Enabled True
Write-Host "[OK] Firewall allows FTP control"

# --- Allow outbound ports for basic functionality ---
New-NetFirewallRule -DisplayName "CCDC-DNS-TCP" -Direction Outbound -Action Allow -Protocol TCP -RemotePort 53 -Profile Any | Out-Null
New-NetFirewallRule -DisplayName "CCDC-DNS-UDP" -Direction Outbound -Action Allow -Protocol UDP -RemotePort 53 -Profile Any | Out-Null
New-NetFirewallRule -DisplayName "CCDC-HTTP-HTTPS" -Direction Outbound -Action Allow -Protocol TCP -RemotePort 80,443 -Profile Any | Out-Null

# --- Allow outbound for domain ports ---
New-NetFirewallRule -DisplayName "CCDC-Kerberos-TCP" -Direction Outbound -Action Allow -Protocol TCP -RemotePort 88,464 -Profile Any | Out-Null
New-NetFirewallRule -DisplayName "CCDC-Kerberos-UDP" -Direction Outbound -Action Allow -Protocol UDP -RemotePort 88,464 -Profile Any | Out-Null

New-NetFirewallRule -DisplayName "CCDC-LDAP-LDAPS-TCP" -Direction Outbound -Action Allow -Protocol TCP -RemotePort 389,636 -Profile Any | Out-Null
New-NetFirewallRule -DisplayName "CCDC-LDAP-UDP" -Direction Outbound -Action Allow -Protocol UDP -RemotePort 389 -Profile Any | Out-Null

New-NetFirewallRule -DisplayName "CCDC-GC" -Direction Outbound -Action Allow -Protocol TCP -RemotePort 3268,3269 -Profile Any | Out-Null

New-NetFirewallRule -DisplayName "CCDC-SMB" -Direction Outbound -Action Allow -Protocol TCP -RemotePort 445 -Profile Any | Out-Null

New-NetFirewallRule -DisplayName "CCDC-RPC" -Direction Outbound -Action Allow -Protocol TCP -RemotePort 135,49152-65535 -Profile Any | Out-Null

New-NetFirewallRule -DisplayName "CCDC-NTP" -Direction Outbound -Action Allow -Protocol TCP -RemotePort 123 -Profile Any | Out-Null

New-NetFirewallRule -DisplayName "CCDC-ICMP" -Direction Outbound -Action Allow -Protocol ICMPv4 -Profile Any | Out-Null

# --- Allow ports for logging ---

New-NetFirewallRule -DisplayName "CCDC-Wazuh-Outbound" -Direction Outbound -Action Allow -Protocol TCP -RemotePort 1514,1515 -Profile Any | Out-Null
New-NetFirewallRule -DisplayName "CCDC-Wazuh-Inbound" -Direction Inbound -Action Allow -Protocol TCP -RemotePort 1514,1515 -Profile Any | Out-Null

New-NetFirewallRule -DisplayName "CCDC-Splunk" -Direction Outbound -Action Allow -Protocol TCP -RemotePort 8089-9997 -Profile Any | Out-Null

# --- Management: lock RDP to admin CIDRs (or disable) ---
if ($AllowRdp) {
  # Remove broad RDP allows (best-effort)
  Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Disable-NetFirewallRule -ErrorAction SilentlyContinue | Out-Null
  foreach ($cidr in $AdminMgmtCIDRs) {
    New-NetFirewallRule -DisplayName "CCDC-RDP-Admin-$cidr" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3389 -RemoteAddress $cidr -Profile Any | Out-Null
  }
  Write-Host "[OK] RDP restricted to admin CIDRs: $($AdminMgmtCIDRs -join ', ')"
} else {
  Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Disable-NetFirewallRule -ErrorAction SilentlyContinue | Out-Null
  New-NetFirewallRule -DisplayName "CCDC-Block-RDP" -Direction Inbound -Action Block -Protocol TCP -LocalPort 3389 -Profile Any | Out-Null
  Write-Host "[OK] RDP blocked."
}

# --- Optional: IIS FTP knobs (only if role is installed) ---
# This does NOT create an FTP site. It only tries to enforce SSL if your site exists.
if ($EnableFtpsOnly) {
  try {
    Import-Module WebAdministration -ErrorAction Stop
    # Require SSL for all FTP sites (applies where FTP is configured)
    Set-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST" `
      -filter "system.ftpServer/security/ssl" -name "controlChannelPolicy" -value "SslRequire" | Out-Null
    Set-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST" `
      -filter "system.ftpServer/security/ssl" -name "dataChannelPolicy" -value "SslRequire" | Out-Null
    Write-Host "[OK] IIS FTP set to require SSL on control+data channels (FTPS-only)."
  } catch {
    Write-Host "[..] WebAdministration/IIS not present or failed to set FTPS-only: $($_.Exception.Message)"
  }
}

Write-Host "=== Done. Reboot recommended if you changed features (SMBv1). ==="
