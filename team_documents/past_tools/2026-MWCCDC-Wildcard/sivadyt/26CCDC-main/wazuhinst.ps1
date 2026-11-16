# wazuh-install.ps1
$ErrorActionPreference = "Stop"

# --- Admin check ---
if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run as Administrator"
}

# --- Vars ---
$WAZUH_VER = "4.14.2-1"
$MSI_URL  = "https://packages.wazuh.com/4.x/windows/wazuh-agent-$WAZUH_VER.msi"
$TMP      = $env:TEMP
$MSI_PATH = Join-Path $TMP "wazuh-agent-$WAZUH_VER.msi"

# --- Input ---
$managerIp = Read-Host "Wazuh Manager IP"
$agentName = Read-Host "Wazuh Agent Name"

# --- TLS fix ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "[*] Downloading MSI..."
Invoke-WebRequest -Uri $MSI_URL -OutFile $MSI_PATH -UseBasicParsing

Write-Host "[*] Installing..."
$msiArgs = @(
    "/i `"$MSI_PATH`"",
    "/qn",
    "WAZUH_MANAGER=$managerIp",
    "WAZUH_AGENT_NAME=$agentName"
)

Start-Process msiexec.exe -ArgumentList $msiArgs -Wait

# --- Start service ---
Write-Host "[*] Starting service..."
Start-Sleep -Seconds 3
Get-Service wazuhsvc -ErrorAction Stop | Start-Service