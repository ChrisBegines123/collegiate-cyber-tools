<# 
Web Server Firewall Baseline (Windows Server 2019)
Asks ONLY for: DNS IPs, NTP IPs, Internal subnets
Ports allowed: 53, 80, 123, 443 (and ONLY those)
- Inbound: TCP 80/443
- Outbound: DNS 53 TCP/UDP (to DNS IPs), NTP 123 UDP (to NTP IPs),
           Web 80/443 TCP (any),
           Internal subnet: TCP 53/80/443 + UDP 53/123
- Blocks inbound RDP/SSH
- Default inbound/outbound: BLOCK
- Logging via netsh
Run as Administrator.
#>

$ErrorActionPreference = "Stop"

function Assert-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this script as Administrator."
  }
}

function Split-List([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return @() }
  return ($s -split "[,\s]+" | Where-Object { $_ -ne "" } | Sort-Object -Unique)
}

function Ensure-RuleGroupOff([string]$groupName) {
  $rules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayGroup -eq $groupName }
  if ($rules) { $rules | Disable-NetFirewallRule | Out-Null }
}

Assert-Admin

Write-Host ""
Write-Host "=== Web Server 2019 Firewall Setup ===" -ForegroundColor Cyan
Write-Host "Inbound: ONLY TCP 80/443 allowed."
Write-Host "Outbound: ONLY 53,80,123,443 allowed (scoped where appropriate)."
Write-Host ""

$dnsServers      = Read-Host "Enter DNS server IP(s) (comma-separated) (example: 172.20.240.202,8.8.8.8)"
$ntpServers      = Read-Host "Enter NTP server IP(s) (comma-separated) (example: 172.20.240.202)"
$internalSubnets = Read-Host "Enter internal subnet(s) CIDR (comma-separated) (example: 172.20.240.0/24,10.0.0.0/8)"

$dnsList    = Split-List $dnsServers
$ntpList    = Split-List $ntpServers
$subnetList = Split-List $internalSubnets

Write-Host ""
Write-Host "Applying firewall policy..." -ForegroundColor Cyan

# Default block (no NotifyOnListen / LogBlocked here to avoid GpoBoolean issues)
Set-NetFirewallProfile -Profile Domain,Private,Public `
  -DefaultInboundAction Block `
  -DefaultOutboundAction Block | Out-Null

# Logging via netsh (reliable)
$logPath = "$env:SystemRoot\System32\LogFiles\Firewall\pfirewall.log"
& netsh advfirewall set allprofiles logging filename "`"$logPath`"" | Out-Null
& netsh advfirewall set allprofiles logging maxfilesize 16384 | Out-Null
& netsh advfirewall set allprofiles logging droppedconnections enable | Out-Null
& netsh advfirewall set allprofiles logging allowedconnections enable | Out-Null

# Remove old rules from this script
Get-NetFirewallRule -ErrorAction SilentlyContinue |
  Where-Object { $_.Group -eq "CCDC-WebServer" } |
  Remove-NetFirewallRule -ErrorAction SilentlyContinue | Out-Null

# Disable built-in Remote Desktop rules if present
Ensure-RuleGroupOff "Remote Desktop"

# -------------------
# INBOUND (Only web)
# -------------------
New-NetFirewallRule -DisplayName "WS IN Allow HTTP 80"   -Group "CCDC-WebServer" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 80  -Profile Domain,Private,Public | Out-Null
New-NetFirewallRule -DisplayName "WS IN Allow HTTPS 443" -Group "CCDC-WebServer" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 443 -Profile Domain,Private,Public | Out-Null

# Explicitly block admin ports inbound
New-NetFirewallRule -DisplayName "WS IN Block RDP 3389" -Group "CCDC-WebServer" -Direction Inbound -Action Block -Protocol TCP -LocalPort 3389 -Profile Domain,Private,Public | Out-Null
New-NetFirewallRule -DisplayName "WS IN Block SSH 22"   -Group "CCDC-WebServer" -Direction Inbound -Action Block -Protocol TCP -LocalPort 22   -Profile Domain,Private,Public | Out-Null
# --- Allow ports for logging ---

New-NetFirewallRule -DisplayName "CCDC-Wazuh-Outbound" -Direction Outbound -Action Allow -Protocol TCP -RemotePort 1514,1515 -Profile Any | Out-Null
New-NetFirewallRule -DisplayName "CCDC-Wazuh-Inbound" -Direction Inbound -Action Allow -Protocol TCP -RemotePort 1514,1515 -Profile Any | Out-Null

New-NetFirewallRule -DisplayName "CCDC-Splunk" -Direction Outbound -Action Allow -Protocol TCP -RemotePort 8089-9997 -Profile Any | Out-Null
# -------------------
# OUTBOUND (Only 53/80/123/443)
# -------------------

# DNS (TCP/UDP 53) - restrict to DNS servers if provided, else allow any
if ($dnsList.Count -gt 0) {
  New-NetFirewallRule -DisplayName "WS OUT Allow DNS UDP 53 -> DNS servers" -Group "CCDC-WebServer" -Direction Outbound -Action Allow -Protocol UDP -RemotePort 53 -RemoteAddress $dnsList -Profile Domain,Private,Public | Out-Null
  New-NetFirewallRule -DisplayName "WS OUT Allow DNS TCP 53 -> DNS servers" -Group "CCDC-WebServer" -Direction Outbound -Action Allow -Protocol TCP -RemotePort 53 -RemoteAddress $dnsList -Profile Domain,Private,Public | Out-Null
} else {
  New-NetFirewallRule -DisplayName "WS OUT Allow DNS UDP 53 (any)" -Group "CCDC-WebServer" -Direction Outbound -Action Allow -Protocol UDP -RemotePort 53 -Profile Domain,Private,Public | Out-Null
  New-NetFirewallRule -DisplayName "WS OUT Allow DNS TCP 53 (any)" -Group "CCDC-WebServer" -Direction Outbound -Action Allow -Protocol TCP -RemotePort 53 -Profile Domain,Private,Public | Out-Null
}

# NTP (UDP 123) - restrict to NTP servers if provided, else allow any
if ($ntpList.Count -gt 0) {
  New-NetFirewallRule -DisplayName "WS OUT Allow NTP UDP 123 -> NTP servers" -Group "CCDC-WebServer" -Direction Outbound -Action Allow -Protocol UDP -RemotePort 123 -RemoteAddress $ntpList -Profile Domain,Private,Public | Out-Null
} else {
  New-NetFirewallRule -DisplayName "WS OUT Allow NTP UDP 123 (any)" -Group "CCDC-WebServer" -Direction Outbound -Action Allow -Protocol UDP -RemotePort 123 -Profile Domain,Private,Public | Out-Null
}

# Web outbound (TCP 80/443) - allow to anywhere
New-NetFirewallRule -DisplayName "WS OUT Allow HTTP 80"   -Group "CCDC-WebServer" -Direction Outbound -Action Allow -Protocol TCP -RemotePort 80  -Profile Domain,Private,Public | Out-Null
New-NetFirewallRule -DisplayName "WS OUT Allow HTTPS 443" -Group "CCDC-WebServer" -Direction Outbound -Action Allow -Protocol TCP -RemotePort 443 -Profile Domain,Private,Public | Out-Null

# Internal subnet access (ONLY these ports) - if provided
if ($subnetList.Count -gt 0) {
  # Internal TCP allowed: 53,80,443
  New-NetFirewallRule -DisplayName "WS OUT Allow INTERNAL TCP 53,80,443" -Group "CCDC-WebServer" -Direction Outbound -Action Allow -Protocol TCP -RemotePort 53,80,443 -RemoteAddress $subnetList -Profile Domain,Private,Public | Out-Null
  # Internal UDP allowed: 53,123
  New-NetFirewallRule -DisplayName "WS OUT Allow INTERNAL UDP 53,123"    -Group "CCDC-WebServer" -Direction Outbound -Action Allow -Protocol UDP -RemotePort 53,123   -RemoteAddress $subnetList -Profile Domain,Private,Public | Out-Null
} else {
  Write-Host "No internal subnet(s) provided; internal-specific outbound rules skipped." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Firewall log: $logPath"
Write-Host ""
Write-Host "Show rules:"
Write-Host "  Get-NetFirewallRule -Group 'CCDC-WebServer' | ft DisplayName,Enabled,Direction,Action -Auto"
Write-Host "Show defaults:"
Write-Host "  Get-NetFirewallProfile | ft Name,DefaultInboundAction,DefaultOutboundAction"
