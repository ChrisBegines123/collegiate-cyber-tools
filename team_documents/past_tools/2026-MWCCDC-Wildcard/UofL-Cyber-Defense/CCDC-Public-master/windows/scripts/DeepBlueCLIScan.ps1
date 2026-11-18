# ----
# DeepBlueCLI Scan-Only Script
# ----

$DeepBlueDir = "C:\Tools\DeepBlueCLI"
$LogDir      = "C:\Logs\DeepBlueCLI"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LogFile   = Join-Path $LogDir "DeepBlueCLI_$Timestamp.log"

$DeepBlueScript = Join-Path $DeepBlueDir "DeepBlue.ps1"
if (-not (Test-Path $DeepBlueScript)) {
    "DeepBlueCLI not installed. Scan skipped." | Out-File $LogFile
    exit 1
}

try {
    Set-Location $DeepBlueDir

    "=== DeepBlueCLI Scan Started: $(Get-Date) ===" | Out-File $LogFile

    & $DeepBlueScript `
        -Log Security `
        -OutputFormat Text `
        2>&1 | Tee-Object -Append -FilePath $LogFile

    "=== DeepBlueCLI Scan Completed: $(Get-Date) ===" | Out-File $LogFile -Append
}
catch {
    "DeepBlueCLI execution failed: $_" | Out-File $LogFile -Append
    exit 1
}
