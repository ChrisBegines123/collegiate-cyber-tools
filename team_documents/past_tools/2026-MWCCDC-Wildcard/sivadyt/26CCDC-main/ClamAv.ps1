Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run PowerShell as Administrator."
  }
}
function Ensure-Dir([string]$Path) {
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Write-CleanConfig {
  param(
    [Parameter(Mandatory)] [string]$SourceSample,
    [Parameter(Mandatory)] [string]$DestConf,
    [Parameter(Mandatory)] [string]$DatabaseDir
  )

  $lines = Get-Content -Path $SourceSample -ErrorAction Stop

  # Remove "Example" / "# Example"
  $lines = $lines | Where-Object { $_ -notmatch '^\s*#?\s*Example\s*$' }

  # Force DatabaseDirectory (replace if present, add if missing)
  $hadDb = $false
  $out = foreach ($l in $lines) {
    if ($l -match '^\s*#?\s*DatabaseDirectory(\s+.*)?$') {
      $hadDb = $true
      "DatabaseDirectory `"$DatabaseDir`""
    } else {
      $l
    }
  }
  if (-not $hadDb) { $out += "DatabaseDirectory `"$DatabaseDir`"" }

  # Safety: if any directive is present with NO args (e.g. "DatabaseDirectory" alone), comment it out
  $out = $out | ForEach-Object {
    if ($_ -match '^\s*(DatabaseDirectory|UpdateLogFile|LogFile|PidFile)\s*$') { "# $_" } else { $_ }
  }

  Set-Content -Path $DestConf -Value $out -Encoding UTF8
}

# ---------------- MAIN ----------------
Assert-Admin

$msiUrl  = "https://www.clamav.net/downloads/production/clamav-1.5.1.win.x64.msi"
$tempDir = Join-Path $env:TEMP "clamav_msi"
$msiPath = Join-Path $tempDir "clamav-1.5.1.win.x64.msi"

$installDir = Join-Path ${env:ProgramFiles} "ClamAV"
$dbDir      = Join-Path $installDir "database"
$confExDir  = Join-Path $installDir "conf_examples"

Ensure-Dir $tempDir

Write-Host "[*] Downloading MSI..."
Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing

Write-Host "[*] Installing ClamAV (silent)..."
$proc = Start-Process -FilePath "msiexec.exe" -ArgumentList @("/i", "`"$msiPath`"", "/qn", "/norestart") -Wait -PassThru
if ($proc.ExitCode -ne 0) { throw "MSI install failed. Exit code: $($proc.ExitCode)" }

if (-not (Test-Path $installDir)) { throw "Install dir not found: $installDir" }
Ensure-Dir $dbDir

$clamdSample = Join-Path $confExDir "clamd.conf.sample"
$freshSample = Join-Path $confExDir "freshclam.conf.sample"
if (-not (Test-Path $clamdSample)) { throw "Missing: $clamdSample" }
if (-not (Test-Path $freshSample)) { throw "Missing: $freshSample" }

$clamdConf = Join-Path $installDir "clamd.conf"
$freshConf = Join-Path $installDir "freshclam.conf"

Write-Host "[*] Writing cleaned configs..."
Write-CleanConfig -SourceSample $clamdSample -DestConf $clamdConf -DatabaseDir $dbDir
Write-CleanConfig -SourceSample $freshSample -DestConf $freshConf -DatabaseDir $dbDir

Write-Host "[*] Running freshclam..."
$freshclamExe = Join-Path $installDir "freshclam.exe"
if (-not (Test-Path $freshclamExe)) { throw "freshclam.exe not found: $freshclamExe" }

& $freshclamExe "--config-file=$freshConf"

Write-Host "`n[✔] Done."
