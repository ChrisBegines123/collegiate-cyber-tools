#Requires -RunAsAdministrator
# WebMail-Hardening.ps1 (Windows Server / IIS)
# Opinionated CCDC hardening for a WebMail host (base OS + IIS).
# Does NOT install WebMail. It hardens the box + IIS if present.

$ErrorActionPreference = "Stop"

# ---- EDIT ME ----
$WebPorts          = @(443)                 # add 80 only if you must
$AllowHTTP         = $false                 # if $true, allow 80 in firewall
$AdminMgmtCIDRs    = @("172.20.240.0/24")   # admin VLAN(s) allowed for RDP/WinRM
$AllowRdp          = $true
$AllowWinRM        = $false                # set $true only if you need it
$DisableSMBv1      = $true
$DisableLLMNR      = $true
$DisableNetBIOS    = $true
$DisableSpooler    = $true
$DisableRemoteReg  = $true
$DisableWebDAV     = $true                 # common lateral move path on IIS
$EnableIISHardening= $true                 # skip if not IIS
# ------------------

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

Write-Host "=== WebMail Host Hardening (Windows/IIS) ==="

# --- Kill common attack surface services ---
if ($DisableSpooler)   { Disable-ServiceSafe "Spooler" }
if ($DisableRemoteReg) { Disable-ServiceSafe "RemoteRegistry" }

Disable-ServiceSafe "Fax"
Disable-ServiceSafe "BluetoothSupportService"
Disable-ServiceSafe "CscService"   # Offline Files
Disable-ServiceSafe "WerSvc"       # WER (optional)

if (-not $AllowWinRM) { Disable-ServiceSafe "WinRM" }

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

# --- NetBIOS over TCP/IP OFF ---
if ($DisableNetBIOS) {
  Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled=TRUE" |
    ForEach-Object { $_.SetTcpipNetbios(2) | Out-Null }
  Write-Host "[OK] NetBIOS disabled on IP-enabled adapters."
}

# --- PowerShell logging (visibility) ---
Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" "EnableScriptBlockLogging" 1
Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging" "EnableModuleLogging" 1
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames" -Force | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames" -Name "*" -PropertyType String -Value "*" -Force | Out-Null
Write-Host "[OK] PowerShell logging enabled."

# --- Audit (minimum useful set) ---
auditpol /set /category:"Logon/Logoff" /success:enable /failure:enable | Out-Null
auditpol /set /category:"Account Logon" /success:enable /failure:enable | Out-Null
auditpol /set /category:"Account Management" /success:enable /failure:enable | Out-Null
auditpol /set /category:"Policy Change" /success:enable /failure:enable | Out-Null
auditpol /set /subcategory:"Process Creation" /success:enable /failure:disable | Out-Null
Write-Host "[OK] Audit policy enabled."

# --- Firewall baseline ---
netsh advfirewall set allprofiles state on | Out-Null
netsh advfirewall set allprofiles firewallpolicy blockinbound,allowoutbound | Out-Null
Write-Host "[OK] Firewall enabled + inbound blocked by default."

# Allow Web ports
foreach ($p in $WebPorts) {
  New-NetFirewallRule -DisplayName "CCDC-WEB-$p" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $p -Profile Any | Out-Null
}
Write-Host "[OK] Allowed inbound web ports: $($WebPorts -join ', ')"

# Optionally allow 80
if ($AllowHTTP -and ($WebPorts -notcontains 80)) {
  New-NetFirewallRule -DisplayName "CCDC-WEB-80" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 80 -Profile Any | Out-Null
}

# RDP locked down (or blocked)
if ($AllowRdp) {
  Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Disable-NetFirewallRule -ErrorAction SilentlyContinue | Out-Null
  foreach ($cidr in $AdminMgmtCIDRs) {
    New-NetFirewallRule -DisplayName "CCDC-RDP-Admin-$cidr" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3389 -RemoteAddress $cidr -Profile Any | Out-Null
  }
  Write-Host "[OK] RDP restricted to: $($AdminMgmtCIDRs -join ', ')"
} else {
  Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Disable-NetFirewallRule -ErrorAction SilentlyContinue | Out-Null
  New-NetFirewallRule -DisplayName "CCDC-Block-RDP" -Direction Inbound -Action Block -Protocol TCP -LocalPort 3389 -Profile Any | Out-Null
  Write-Host "[OK] RDP blocked."
}

# WinRM locked down (optional)
if ($AllowWinRM) {
  foreach ($cidr in $AdminMgmtCIDRs) {
    New-NetFirewallRule -DisplayName "CCDC-WinRM-5985-$cidr" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5985 -RemoteAddress $cidr -Profile Any | Out-Null
    New-NetFirewallRule -DisplayName "CCDC-WinRM-5986-$cidr" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5986 -RemoteAddress $cidr -Profile Any | Out-Null
  }
  Write-Host "[OK] WinRM restricted to: $($AdminMgmtCIDRs -join ', ')"
}

# --- IIS hardening (if IIS installed) ---
if ($EnableIISHardening) {
  try {
    Import-Module WebAdministration -ErrorAction Stop

    # Remove/disable WebDAV (if present)
    if ($DisableWebDAV) {
      Disable-WindowsOptionalFeature -Online -FeatureName IIS-WebDAV -NoRestart -ErrorAction SilentlyContinue | Out-Null
      Write-Host "[OK] WebDAV feature disabled (if installed)."
    }

    # Turn off directory browsing globally
    Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" -Filter "system.webServer/directoryBrowse" -Name "enabled" -Value $false | Out-Null
    Write-Host "[OK] IIS directory browsing disabled."

    # Request filtering: block double-extensions + high-risk verbs, limit uploads (adjust if WebMail needs larger)
    Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" -Filter "system.webServer/security/requestFiltering" -Name "allowDoubleEscaping" -Value $false | Out-Null
    Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" -Filter "system.webServer/security/requestFiltering/requestLimits" -Name "maxAllowedContentLength" -Value 30000000 | Out-Null # ~30MB
    Write-Host "[OK] IIS request filtering set (double escaping off, max upload ~30MB)."

    # Add simple security headers (global)
    $hdrPath = "MACHINE/WEBROOT/APPHOST"
    $hdrFilter = "system.webServer/httpProtocol/customHeaders"
    function Upsert-Header($name,$value){
      $existing = Get-WebConfigurationProperty -PSPath $hdrPath -Filter "$hdrFilter/add[@name='$name']" -Name "." -ErrorAction SilentlyContinue
      if ($existing) {
        Set-WebConfigurationProperty -PSPath $hdrPath -Filter "$hdrFilter/add[@name='$name']" -Name "value" -Value $value | Out-Null
      } else {
        Add-WebConfigurationProperty -PSPath $hdrPath -Filter $hdrFilter -Name "." -Value @{name=$name;value=$value} | Out-Null
      }
    }
    Upsert-Header "X-Content-Type-Options" "nosniff"
    Upsert-Header "X-Frame-Options" "DENY"
    Upsert-Header "Referrer-Policy" "no-referrer"
    Upsert-Header "X-XSS-Protection" "0"
    Write-Host "[OK] IIS security headers set."

    # Prefer HTTPS: if 80 exists, you should add a redirect in your site config (app-specific).
    Write-Host "[..] Note: HTTP->HTTPS redirect is site/app-specific; not forced globally here."

  } catch {
    Write-Host "[..] IIS/WebAdministration not present or failed: $($_.Exception.Message)"
  }
}

Write-Host "=== Done. Reboot recommended if features changed (SMBv1/WebDAV). ==="
