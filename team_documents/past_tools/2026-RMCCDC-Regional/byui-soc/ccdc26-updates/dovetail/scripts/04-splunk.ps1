#Requires -RunAsAdministrator
# CCDC26 - Splunk Universal Forwarder Deployment (SELF-CONTAINED)
# Downloads, installs, configures, and starts the Splunk UF.
# Reads server from C:\ccdc26\config.ps1 if available, else uses parameter.

param(
    [string]$SplunkServer = "",
    [string]$SplunkPort = "9997",
    [string]$SplunkVersion = "9.3.1",
    [string]$SplunkBuild = "0b8d769cb912"
)

$ErrorActionPreference = "Continue"

$LogDir = "C:\ccdc26\logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Info { param([string]$M) Write-Host "[*] $M" -ForegroundColor Cyan }
function OK   { param([string]$M) Write-Host "[+] $M" -ForegroundColor Green }
function Warn { param([string]$M) Write-Host "[!] $M" -ForegroundColor Yellow }
function Err  { param([string]$M) Write-Host "[-] $M" -ForegroundColor Red }
function Log  { param([string]$M) $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"; "$ts - $M" | Out-File "$LogDir\splunk-setup.log" -Append -Encoding UTF8 }

# Try loading config
$cfgPath = "C:\ccdc26\config.ps1"
if (Test-Path $cfgPath) { . $cfgPath }
if (-not $SplunkServer -and $script:EnvConfig) {
    $cfg = $script:EnvConfig
    if ($cfg.SplunkServer)  { $SplunkServer  = $cfg.SplunkServer }
    if ($cfg.SplunkPort)    { $SplunkPort    = $cfg.SplunkPort }
    if ($cfg.SplunkVersion) { $SplunkVersion = $cfg.SplunkVersion }
    if ($cfg.SplunkBuild)   { $SplunkBuild   = $cfg.SplunkBuild }
}

if (-not $SplunkServer) {
    Err "SplunkServer not specified. Use -SplunkServer or set in config.ps1"
    exit 1
}

$SPLUNK_HOME = "C:\Program Files\SplunkUniversalForwarder"
$MSI_URL = "https://download.splunk.com/products/universalforwarder/releases/$SplunkVersion/windows/splunkforwarder-$SplunkVersion-$SplunkBuild-windows-x64.msi"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Splunk Forwarder Deployment" -ForegroundColor Cyan
Write-Host "  Server: ${SplunkServer}:${SplunkPort}" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ── Install ──
if (-not (Test-Path "$SPLUNK_HOME\bin\splunk.exe")) {
    Info "Downloading Splunk UF..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $msiPath = "$env:TEMP\splunkforwarder.msi"

    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($MSI_URL, $msiPath)
        OK "Downloaded Splunk UF"
    } catch {
        Err "Download failed: $_"
        Warn "Manual download: $MSI_URL"
        exit 1
    }

    Info "Installing Splunk UF (silent)..."
    $installArgs = "/i `"$msiPath`" AGREETOLICENSE=yes RECEIVING_INDEXER=`"${SplunkServer}:${SplunkPort}`" LAUNCHSPLUNK=0 /quiet"
    Start-Process msiexec.exe -ArgumentList $installArgs -Wait -NoNewWindow
    Remove-Item $msiPath -Force -ErrorAction SilentlyContinue

    if (Test-Path "$SPLUNK_HOME\bin\splunk.exe") {
        OK "Splunk UF installed"
    } else {
        Err "Installation failed"
        exit 1
    }
} else {
    Info "Splunk UF already installed"
}

# ── Configure outputs.conf ──
Info "Configuring outputs.conf..."
$localDir = "$SPLUNK_HOME\etc\system\local"
if (-not (Test-Path $localDir)) { New-Item -ItemType Directory -Path $localDir -Force | Out-Null }

@"
[tcpout]
defaultGroup = ccdc_splunk

[tcpout:ccdc_splunk]
server = ${SplunkServer}:${SplunkPort}
compressed = true

[tcpout-server://${SplunkServer}:${SplunkPort}]
"@ | Set-Content "$localDir\outputs.conf" -Encoding UTF8

# ── Configure inputs.conf ──
Info "Configuring inputs.conf..."
@"
[default]
host = $env:COMPUTERNAME

[WinEventLog://Security]
disabled = false
index = windows
sourcetype = WinEventLog:Security
evt_resolve_ad_obj = 1
checkpointInterval = 5

[WinEventLog://System]
disabled = false
index = windows
sourcetype = WinEventLog:System

[WinEventLog://Application]
disabled = false
index = windows
sourcetype = WinEventLog:Application

[WinEventLog://Microsoft-Windows-PowerShell/Operational]
disabled = false
index = windows
sourcetype = WinEventLog:PowerShell

[WinEventLog://PowerShellCore/Operational]
disabled = false
index = windows
sourcetype = WinEventLog:PowerShell

[WinEventLog://Microsoft-Windows-Sysmon/Operational]
disabled = false
index = windows
sourcetype = WinEventLog:Sysmon
renderXml = true

[WinEventLog://Microsoft-Windows-Windows Defender/Operational]
disabled = false
index = windows
sourcetype = WinEventLog:Defender

[WinEventLog://Microsoft-Windows-Windows Firewall With Advanced Security/Firewall]
disabled = false
index = windows
sourcetype = WinEventLog:Firewall

[WinEventLog://Microsoft-Windows-TaskScheduler/Operational]
disabled = false
index = windows
sourcetype = WinEventLog:TaskScheduler

[WinEventLog://Microsoft-Windows-TerminalServices-LocalSessionManager/Operational]
disabled = false
index = windows
sourcetype = WinEventLog:RDP

[WinEventLog://Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational]
disabled = false
index = windows
sourcetype = WinEventLog:RDP

[WinEventLog://Microsoft-Windows-WinRM/Operational]
disabled = false
index = windows
sourcetype = WinEventLog:WinRM

[WinEventLog://Microsoft-Windows-WMI-Activity/Operational]
disabled = false
index = windows
sourcetype = WinEventLog:WMI

[WinEventLog://Microsoft-Windows-SMBServer/Security]
disabled = false
index = windows
sourcetype = WinEventLog:SMB

[WinEventLog://DNS Server]
disabled = false
index = windows
sourcetype = WinEventLog:DNS

[WinEventLog://Directory Service]
disabled = false
index = windows
sourcetype = WinEventLog:DirectoryService
"@ | Set-Content "$localDir\inputs.conf" -Encoding UTF8

OK "Splunk inputs configured (Security, System, Application, PowerShell, Sysmon, Defender, DNS, Firewall, TaskScheduler, RDP, WinRM, WMI, SMB)"

# ── Start service ──
Info "Starting Splunk forwarder..."
& "$SPLUNK_HOME\bin\splunk.exe" start --accept-license --answer-yes --no-prompt 2>$null | Out-Null
Set-Service -Name "SplunkForwarder" -StartupType Automatic -ErrorAction SilentlyContinue

$svc = Get-Service -Name "SplunkForwarder" -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq "Running") {
    OK "Splunk forwarder running"
} else {
    Warn "Splunk service may not have started -- check manually"
}

# ── Verify connectivity ──
Info "Testing connectivity to ${SplunkServer}:${SplunkPort}..."
$tc = Test-NetConnection -ComputerName $SplunkServer -Port ([int]$SplunkPort) -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
if ($tc.TcpTestSucceeded) {
    OK "Connection to Splunk server verified"
} else {
    Warn "Cannot reach ${SplunkServer}:${SplunkPort} -- check firewall/routing"
}

Log "Splunk UF deployed to ${SplunkServer}:${SplunkPort}"
Write-Host ""
OK "Splunk forwarder deployment complete!"
