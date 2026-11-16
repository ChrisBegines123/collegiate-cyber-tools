# ----
# Quarantine.ps1
# Put the malware path in $MalwarePath and run the script.
# It will MOVE the file/folder into C:\Quarantine\<timestamp>\ and lock it down so
# normal users cannot read/execute it. Administrators + SYSTEM keep full control.

# This is experiemental and untested. EXPECT BUGS
# ----

# ======================
# CONFIG YOU EDIT
# ======================
$MalwarePath     = "C:\Path\To\Suspicious\FileOrFolder"   # <-- paste the malware path here
$QuarantineRoot  = "C:\Quarantine"
$CopyOnly        = $false   # $true = copy; $false = move

# ======================
# Logging (optional)
# ======================
$LogDir = "C:\Logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$TimestampName = Get-Date -Format "yyyyMMdd_HHmmss"
$TranscriptLog = Join-Path $LogDir "Quarantine_$TimestampName.log"
Start-Transcript -Path $TranscriptLog | Out-Null

function Write-Status {
    param([string]$Message, [ValidateSet("Info","Success","Warning","Error")][string]$Level="Info")
    switch ($Level) {
        "Success" { Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
        "Warning" { Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
        "Error"   { Write-Host "[ERROR] $Message"   -ForegroundColor Red }
        default   { Write-Host "[INFO] $Message" }
    }
}

function Ensure-QuarantineRoot {
    param([string]$Root)

    if (-not (Test-Path $Root)) {
        New-Item -ItemType Directory -Path $Root -Force | Out-Null
    }

    # Lock down root: only Administrators + SYSTEM
    & icacls $Root /inheritance:r | Out-Null
    & icacls $Root /grant:r "Administrators:(OI)(CI)(F)" "SYSTEM:(OI)(CI)(F)" | Out-Null

    # Deny read/execute to typical user groups (prevents browsing/execution)
    & icacls $Root /deny "Users:(OI)(CI)(RX)" "Authenticated Users:(OI)(CI)(RX)" "Everyone:(OI)(CI)(RX)" | Out-Null
}

function New-QuarantineSubfolder {
    param([string]$Root)

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $dest  = Join-Path $Root $stamp
    New-Item -ItemType Directory -Path $dest -Force | Out-Null

    # Same lockdown on subfolder
    & icacls $dest /inheritance:r | Out-Null
    & icacls $dest /grant:r "Administrators:(OI)(CI)(F)" "SYSTEM:(OI)(CI)(F)" | Out-Null
    & icacls $dest /deny "Users:(OI)(CI)(RX)" "Authenticated Users:(OI)(CI)(RX)" "Everyone:(OI)(CI)(RX)" | Out-Null

    return $dest
}

function Lockdown-Item {
    param([string]$ItemPath)

    # Hard lockdown: only Administrators + SYSTEM
    & icacls $ItemPath /inheritance:r | Out-Null
    & icacls $ItemPath /grant:r "Administrators:(OI)(CI)(F)" "SYSTEM:(OI)(CI)(F)" | Out-Null
    & icacls $ItemPath /deny "Users:(OI)(CI)(RX)" "Authenticated Users:(OI)(CI)(RX)" "Everyone:(OI)(CI)(RX)" | Out-Null

    # Read-only marker (does not stop admins, but helps prevent accidental edits)
    try { attrib +R $ItemPath /S /D | Out-Null } catch { }
}

function Write-Manifest {
    param(
        [string]$DestFolder,
        [string]$OriginalPath,
        [string]$QuarantinePath
    )

    $manifestPath = Join-Path $DestFolder "manifest.txt"
    $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $type = if (Test-Path $QuarantinePath -PathType Container) { "Directory" } else { "File" }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Timestamp: $now")
    $lines.Add("Type: $type")
    $lines.Add("OriginalPath: $OriginalPath")
    $lines.Add("QuarantinePath: $QuarantinePath")

    if ($type -eq "File") {
        try {
            $hash = Get-FileHash -Path $QuarantinePath -Algorithm SHA256
            $lines.Add("SHA256: $($hash.Hash)")
        } catch {
            $lines.Add("SHA256: ERROR ($($_.Exception.Message))")
        }

        try {
            $sig = Get-AuthenticodeSignature -FilePath $QuarantinePath
            $lines.Add("SignatureStatus: $($sig.Status)")
            if ($sig.SignerCertificate) {
                $lines.Add("Signer: $($sig.SignerCertificate.Subject)")
                $lines.Add("Thumbprint: $($sig.SignerCertificate.Thumbprint)")
            }
        } catch {
            $lines.Add("SignatureStatus: ERROR ($($_.Exception.Message))")
        }

        try {
            $fi = Get-Item $QuarantinePath -Force
            $lines.Add("SizeBytes: $($fi.Length)")
            $lines.Add("LastWriteTime: $($fi.LastWriteTime)")
        } catch { }
    }

    $lines | Out-File -FilePath $manifestPath -Encoding utf8 -Force
}

# ======================
# MAIN
# ======================
if ([string]::IsNullOrWhiteSpace($MalwarePath)) {
    Write-Status "Set `$MalwarePath to the file/folder you want to quarantine." "Error"
    Stop-Transcript | Out-Null
    exit 1
}

if (-not (Test-Path $MalwarePath)) {
    Write-Status "Path not found: $MalwarePath" "Error"
    Stop-Transcript | Out-Null
    exit 1
}

Ensure-QuarantineRoot -Root $QuarantineRoot
$QFolder = New-QuarantineSubfolder -Root $QuarantineRoot

$leaf = Split-Path $MalwarePath -Leaf
$destPath = Join-Path $QFolder $leaf

try {
    if ($CopyOnly) {
        Write-Status "Copying into quarantine: $MalwarePath -> $destPath" "Info"
        Copy-Item -Path $MalwarePath -Destination $destPath -Recurse -Force
    } else {
        Write-Status "Moving into quarantine: $MalwarePath -> $destPath" "Info"
        Move-Item -Path $MalwarePath -Destination $destPath -Force
    }
} catch {
    Write-Status "Failed to move/copy into quarantine: $($_.Exception.Message)" "Error"
    Stop-Transcript | Out-Null
    exit 1
}

Lockdown-Item -ItemPath $destPath
Write-Manifest -DestFolder $QFolder -OriginalPath $MalwarePath -QuarantinePath $destPath

Write-Status "Quarantine complete: $destPath" "Success"
Write-Status "Manifest: $(Join-Path $QFolder 'manifest.txt')" "Info"
Write-Status "Transcript log: $TranscriptLog" "Info"

Stop-Transcript | Out-Null
