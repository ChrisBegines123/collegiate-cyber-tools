# clamav-win-setup.ps1
# Download configs -> install ClamAV MSI -> apply configs -> update DB

$ErrorActionPreference = "Stop"

# --- URLs ---
$WIN_MSI_URL = "https://www.clamav.net/downloads/production/clamav-1.5.1.win.x64.msi"
$CLAMD_CONF_URL = "https://raw.githubusercontent.com/sivadyt/ChainsawMan/refs/heads/main/clamd.conf"
$FRESHCLAM_CONF_URL = "https://raw.githubusercontent.com/sivadyt/ChainsawMan/refs/heads/main/freshclam.conf"

# --- Paths ---
$INSTALL_DIR = "C:\Program Files\ClamAV"
$DB_DIR      = "$INSTALL_DIR\database"

# --- Certs dirs (copy/sync) ---
$CERTS_DIR_INSTALL = "$INSTALL_DIR\certs"
$CERTS_DIR_LEGACY  = "C:\ClamAV\certs"

function Is-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Download-File($Url, $OutFile) {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null
  Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
}

function Find-Exe($name, $roots) {
  foreach ($r in $roots) {
    if (Test-Path $r) {
      $hit = Get-ChildItem $r -Recurse -Filter $name -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($hit) { return $hit.FullName }
    }
  }
  $null
}

if (-not (Is-Admin)) { throw "Run PowerShell as Administrator." }

# --- Temp workspace ---
$tmp = Join-Path $env:TEMP ("clamav_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# --- Download configs FIRST ---
Write-Host "Downloading config files..."
Download-File $CLAMD_CONF_URL     (Join-Path $tmp "clamd.conf")
Download-File $FRESHCLAM_CONF_URL (Join-Path $tmp "freshclam.conf")

# --- Install ClamAV if needed ---
$roots = @($INSTALL_DIR, "C:\Program Files", "C:\Program Files (x86)")
$clamscan = Find-Exe "clamscan.exe" $roots

if (-not $clamscan) {
  $msi = Join-Path $tmp "clamav.msi"
  Download-File $WIN_MSI_URL $msi

  Write-Host "Installing ClamAV..."
  $log = Join-Path $tmp "clamav-install.log"
  $args = "/i `"$msi`" /qn /norestart /l*v `"$log`""
  $p = Start-Process msiexec.exe -ArgumentList $args -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "MSI failed. Log: $log" }

  $clamscan = Find-Exe "clamscan.exe" $roots
  if (-not $clamscan) { throw "Install completed but clamscan.exe not found." }
}

$installDir = Split-Path $clamscan -Parent
$freshclam  = Find-Exe "freshclam.exe" @($installDir, "$installDir\bin", $INSTALL_DIR)

# --- Ensure DB dir ---
New-Item -ItemType Directory -Force -Path $DB_DIR | Out-Null

# --- Ensure certs dirs exist + copy/sync ---
New-Item -ItemType Directory -Force -Path $CERTS_DIR_INSTALL | Out-Null
New-Item -ItemType Directory -Force -Path $CERTS_DIR_LEGACY  | Out-Null

$installHas = ((Get-ChildItem $CERTS_DIR_INSTALL -Force -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
$legacyHas  = ((Get-ChildItem $CERTS_DIR_LEGACY  -Force -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)

if ($installHas -and -not $legacyHas) {
  Copy-Item "$CERTS_DIR_INSTALL\*" $CERTS_DIR_LEGACY -Recurse -Force -ErrorAction SilentlyContinue
} elseif ($legacyHas -and -not $installHas) {
  Copy-Item "$CERTS_DIR_LEGACY\*" $CERTS_DIR_INSTALL -Recurse -Force -ErrorAction SilentlyContinue
} elseif ($installHas -and $legacyHas) {
  # keep them in sync (install -> legacy)
  Copy-Item "$CERTS_DIR_INSTALL\*" $CERTS_DIR_LEGACY -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Apply configs ---
Write-Host "Applying configuration files..."
Copy-Item (Join-Path $tmp "clamd.conf")      "$INSTALL_DIR\clamd.conf"      -Force
Copy-Item (Join-Path $tmp "freshclam.conf")  "$INSTALL_DIR\freshclam.conf" -Force

# --- Update DB ---
Write-Host "Running freshclam..."
& $freshclam --config-file="$INSTALL_DIR\freshclam.conf"

# --- Final check ---
Write-Host ""
& $clamscan --version
Get-ChildItem $DB_DIR

# --- Create Scheduled Task: Hourly ClamAV Scan ---
$taskName = "ClamAV Hourly Scan"

# Remove existing task if present
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$action = New-ScheduledTaskAction `
  -Execute "$INSTALL_DIR\clamscan.exe" `
  -Argument "C:\ --recursive --infected --log=$INSTALL_DIR\logs\hourly-scan.log"

$trigger = New-ScheduledTaskTrigger `
  -Once `
  -At (Get-Date).AddHours(1) `
  -RepetitionInterval (New-TimeSpan -Minutes 60)

$principal = New-ScheduledTaskPrincipal `
  -UserId "SYSTEM" `
  -LogonType ServiceAccount `
  -RunLevel Highest

# Ensure log dir
New-Item -ItemType Directory -Force -Path "$INSTALL_DIR\logs" | Out-Null

Register-ScheduledTask `
  -TaskName $taskName `
  -Action $action `
  -Trigger $trigger `
  -Principal $principal `
  -Description "Runs an hourly ClamAV scan of C: drive."

Write-Host "Scheduled task '$taskName' created."
