# ---- Logging Setup ----
$LogDir = "C:\Logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$TimestampName   = Get-Date -Format "HHmm"
$TranscriptLog   = Join-Path $LogDir "ClamScan_Transcript_$TimestampName.log"
$FullScanResults = Join-Path $LogDir "full_scan_results_$TimestampName.txt"
$DetectionResults= Join-Path $LogDir "detection_results_$TimestampName.txt"

Start-Transcript -Path $TranscriptLog

# ----
# Status Function
# ----
function Write-Status {
 param (
    [Parameter(Mandatory)][string]$Message,
    [ValidateSet("Info","Success","Warning","Error")][string]$Level = "Info"
 )
 switch ($Level) {
    "Success" { Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
    "Warning" { Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
    "Error"   { Write-Host "[ERROR] $Message"   -ForegroundColor Red }
    default   { Write-Host "[INFO] $Message" }
 }
}

# =========================
# CONFIG (Server 2019 / 2GB RAM)
# =========================
$ClamScanPath  = "C:\Program Files\ClamAV\clamscan.exe"

# CPU controls
$MaxCoresToUse  = 1
$PriorityClass  = "BelowNormal"

# Parallelism (KEEP 1 on 2GB RAM)
$MaxParallel    = 1

# Disable watchdog (killing prevents completion on large trees)
$MaxWorkingSetMB = 0

# Exclusions (low value / huge / protected)
$ExcludeDirs = @(
    "C:\Windows\WinSxS",
    "C:\System Volume Information",
    "C:\$Recycle.Bin",
    "C:\Recovery",
    "C:\Windows\SoftwareDistribution\Download",
    "C:\Logs",
    "C:\Users\All Users",
    "C:\Tools",
    "C:\Program Files\ClamAV",
    "C:\Program Files (x86)\ossec-agent"
)

# =========================
# Helpers
# =========================
function Get-LogicalProcessorCount {
    try {
        return (Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    } catch {
        return [Environment]::ProcessorCount
    }
}

function New-AffinityMask {
    param([Parameter(Mandatory)][int]$CoresToUse)

    $total = Get-LogicalProcessorCount
    if ($CoresToUse -lt 1) { $CoresToUse = 1 }
    if ($CoresToUse -gt $total) { $CoresToUse = $total }
    if ($CoresToUse -gt 63) { $CoresToUse = 63 }
    return ([UInt64]1 -shl $CoresToUse) - 1
}

function Start-ClamScanChunkJob {
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$OutFile,
        [Parameter(Mandatory)][UInt64]$AffinityMask
    )

    Start-Job -ScriptBlock {
        param($TargetPath, $ClamScanPath, $ExcludeDirs, $AffinityMask, $PriorityClass, $OutFile, $MaxWorkingSetMB)

        $args = @("-r", $TargetPath, "--infected", "--quiet")
        foreach ($d in $ExcludeDirs) { $args += "--exclude-dir=$d" }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $ClamScanPath
        $psi.Arguments = ($args | ForEach-Object { if ($_ -match '\s') { '"' + $_.Replace('"','\"') + '"' } else { $_ } }) -join ' '
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.CreateNoWindow = $true

        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        [void]$p.Start()

        # CPU limiting
        try { $p.PriorityClass = $PriorityClass } catch { }
        try { $p.ProcessorAffinity = [IntPtr]$AffinityMask } catch { }

        # Optional watchdog (disabled by default here)
        $killedForMemory = $false
        if ($MaxWorkingSetMB -gt 0) {
            $limitBytes = [Int64]$MaxWorkingSetMB * 1MB
            while (-not $p.HasExited) {
                try {
                    $p.Refresh()
                    if ($p.WorkingSet64 -gt $limitBytes) {
                        $killedForMemory = $true
                        try { $p.Kill() } catch { }
                        break
                    }
                } catch { }
                Start-Sleep -Milliseconds 750
            }
        }

        $stdout = ""
        $stderr = ""
        try { $stdout = $p.StandardOutput.ReadToEnd() } catch { }
        try { $stderr = $p.StandardError.ReadToEnd() } catch { }
        try { $p.WaitForExit() } catch { }

        $stdout | Out-File -FilePath $OutFile -Encoding utf8 -Force
        if ($stderr) { "`n--- STDERR ---`n$stderr" | Out-File -FilePath $OutFile -Encoding utf8 -Append }

        if ($killedForMemory) {
            "`n--- WATCHDOG ---`nKilled clamscan due to WorkingSet > ${MaxWorkingSetMB}MB" | Out-File -FilePath $OutFile -Encoding utf8 -Append
            return 99
        }

        return $p.ExitCode
    } -ArgumentList $TargetPath, $ClamScanPath, $ExcludeDirs, $AffinityMask, $PriorityClass, $OutFile, $MaxWorkingSetMB
}

# =========================
# Build Scan Targets (C:\ only, chunked to reduce RAM spikes)
# High-value targets are scanned FIRST
# =========================
if (-not (Test-Path $ClamScanPath)) {
    Write-Status "clamscan.exe not found at: $ClamScanPath" "Error"
    Stop-Transcript
    exit 1
}

Remove-Item $FullScanResults -ErrorAction SilentlyContinue
Remove-Item $DetectionResults -ErrorAction SilentlyContinue

# High-value directories (first)
$HighValue = @(
    "C:\Windows",
    "C:\ProgramData",
    "C:\Users",
    "C:\inetpub"
) | Where-Object { Test-Path $_ }

# Chunk roots (second)
$ChunkRoots = @("C:\Windows", "C:\Program Files", "C:\Program Files (x86)", "C:\Users", "C:\ProgramData")

$ChunkTargets = New-Object System.Collections.Generic.List[string]
foreach ($root in $ChunkRoots) {
    if (-not (Test-Path $root)) { continue }
    if ($ExcludeDirs -icontains $root) { continue }

    Get-ChildItem -Path $root -Directory -Force -ErrorAction SilentlyContinue |
    ForEach-Object {
        $p = $_.FullName

        $excluded = $false
        foreach ($ex in $ExcludeDirs) {
            if ($p -like "$ex*") { $excluded = $true; break }
        }

        if (-not $excluded) {
            $ChunkTargets.Add($p) | Out-Null
        }
    }
}

# Final ordered target list:
#  1) HighValue (in the exact order you listed)
#  2) ChunkTargets (alphabetical, de-duped, and excluding anything already in HighValue)
$ScanTargets =
    @($HighValue) +
    @($ChunkTargets | Sort-Object -Unique | Where-Object { $HighValue -notcontains $_ })

# Final exclude filter (belt & suspenders)
$ScanTargets = $ScanTargets | Where-Object {
    $p = $_
    -not ($ExcludeDirs | Where-Object { $p -like "$_*" })
}

Write-Status "Final scan targets (C:\ only): $($ScanTargets.Count) target(s)" "Info"
Write-Status "Order: High-value targets first, then chunked subdirectories." "Info"
Write-Status "CPU: $MaxCoresToUse core(s), Priority=$PriorityClass, Parallel=$MaxParallel" "Info"
Write-Status "Excluding: $($ExcludeDirs -join '; ')" "Info"

# =========================
# Run scans with throttling (MaxParallel=1)
# =========================
$AffinityMask = New-AffinityMask -CoresToUse $MaxCoresToUse

$jobs = New-Object System.Collections.Generic.List[object]

foreach ($t in $ScanTargets) {
    if (-not (Test-Path $t)) { continue }

    while (@(Get-Job -State Running).Count -ge $MaxParallel) {
        Start-Sleep -Seconds 1
    }

    $safeName = ($t -replace '[:\\]','_')
    $outFile  = Join-Path $LogDir "clamscan_chunk_${safeName}_$TimestampName.out"

    Write-Status "Scanning: $t" "Info"
    $job = Start-ClamScanChunkJob -TargetPath $t -OutFile $outFile -AffinityMask $AffinityMask

    $jobs.Add([pscustomobject]@{ Target=$t; Job=$job; OutFile=$outFile }) | Out-Null
}

if ($jobs.Count -gt 0) {
    Write-Status "Waiting for $($jobs.Count) scan job(s)..." "Info"
    Wait-Job -Job ($jobs.Job) | Out-Null
}

# =========================
# Merge outputs + detections
# =========================
Write-Status "Merging scan outputs..." "Info"

foreach ($j in $jobs) {
    $exitCode = Receive-Job -Job $j.Job -ErrorAction SilentlyContinue
    Remove-Job -Job $j.Job -Force -ErrorAction SilentlyContinue

    if ($exitCode -eq 0) {
        Write-Status "Completed: $($j.Target) (ExitCode=0)" "Success"
    } elseif ($exitCode -eq 1) {
        Write-Status "Infected found in: $($j.Target) (ExitCode=1)" "Warning"
    } elseif ($exitCode -eq 99) {
        Write-Status "Killed for memory limit in: $($j.Target) (ExitCode=99)" "Error"
    } else {
        Write-Status "Completed with ExitCode=${exitCode}: $($j.Target)" "Warning"
    }

    if (Test-Path $j.OutFile) {
        "===== SCAN OUTPUT: $($j.Target) =====" | Out-File $FullScanResults -Encoding utf8 -Append
        Get-Content $j.OutFile | Out-File $FullScanResults -Encoding utf8 -Append

        $foundLines = Get-Content $j.OutFile | Where-Object { $_ -match "FOUND$" }
        if ($foundLines) {
            "===== DETECTIONS: $($j.Target) =====" | Out-File $DetectionResults -Encoding utf8 -Append
            $foundLines | Out-File $DetectionResults -Encoding utf8 -Append
        }
    }
}

Write-Status "ClamScan completed (C:\ only)." "Success"
Write-Status "Full results: $FullScanResults" "Info"
Write-Status "Detections : $DetectionResults" "Info"

# ---- Notify User if Detections Found ----
if (Test-Path $DetectionResults) {
    $Detections = Get-Content $DetectionResults | Where-Object { $_ -match "FOUND$" }
    if ($Detections) {
        [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
        [System.Windows.Forms.MessageBox]::Show(
            "ClamAV detected threats on this system.`nDetections:`n$DetectionResults`nFull output:`n$FullScanResults",
            "ClamAV Detection",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        Write-Status "Detections found. User notified." "Warning"
    } else {
        Write-Status "No threats detected." "Success"
    }
} else {
    Write-Status "No detection file created; assuming no threats found." "Info"
}

Stop-Transcript
