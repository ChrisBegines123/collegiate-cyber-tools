# ==============================================================================
# Script Name : repair-windows-security.ps1
# Description : Fix potential issues with windows security
# Author      : Tyler Olson
# Version     : 1.0
# ==============================================================================

# Log file setup
$LogDir = "C:\Logs"
$LogFile = "$LogDir\windowssec$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$TimeStamp] [$Level] $Message"
    $LogMessage | Out-File -FilePath $LogFile -Append
    switch ($Level) {
        "INFO"    { Write-Host $LogMessage -ForegroundColor Gray }
        "WARNING" { Write-Host $LogMessage -ForegroundColor Yellow }
        "ERROR"   { Write-Host $LogMessage -ForegroundColor Red }
        "SUCCESS" { Write-Host $LogMessage -ForegroundColor Green }
    }
}

# Verify running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "This script requires Administrator privileges. Please restart with elevated permissions." "ERROR"
    exit 1
}

# ==============================================================================
# STEP 1: Retrieve and display current state of malware protections
# ==============================================================================
Write-Log "==============================" "INFO"
Write-Log "STEP 1: Checking current Windows Security / Defender state..." "INFO"
Write-Log "==============================" "INFO"

function Get-DefenderStatus {
    try {
        $mpStatus = Get-MpComputerStatus -ErrorAction Stop

        $checks = @{
            "Antivirus Enabled"              = $mpStatus.AntivirusEnabled
            "Antispyware Enabled"            = $mpStatus.AntispywareEnabled
            "Real-Time Protection Enabled"   = $mpStatus.RealTimeProtectionEnabled
            "Behavior Monitor Enabled"       = $mpStatus.BehaviorMonitorEnabled
            "IOAV Protection Enabled"        = $mpStatus.IoavProtectionEnabled
            "NIS Enabled"                    = $mpStatus.NISEnabled
            "On-Access Protection Enabled"   = $mpStatus.OnAccessProtectionEnabled
            "Tamper Protection Source"       = $mpStatus.TamperProtectionSource
            "Antivirus Signature Age (days)" = $mpStatus.AntivirusSignatureAge
            "Last Full Scan"                 = $mpStatus.FullScanEndTime
            "Last Quick Scan"                = $mpStatus.QuickScanEndTime
        }

        Write-Host "`n--- Windows Defender Status ---" -ForegroundColor Cyan
        foreach ($key in $checks.Keys) {
            $val = $checks[$key]
            $color = if ($val -eq $true) { "Green" } elseif ($val -eq $false) { "Red" } else { "Gray" }
            Write-Host ("  {0,-40} {1}" -f $key, $val) -ForegroundColor $color
            Write-Log "$key : $val" "INFO"
        }
        Write-Host ""

        return $mpStatus
    } catch {
        Write-Log "Failed to retrieve MpComputerStatus. Windows Defender service may not be running. Error: $_" "ERROR"
        return $null
    }
}

function Get-SecurityCenterStatus {
    try {
        $av  = Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName AntiVirusProduct  -ErrorAction Stop
        $fw  = Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName FirewallProduct    -ErrorAction Stop
        $as  = Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName AntiSpywareProduct -ErrorAction Stop

        Write-Host "--- Security Center Registered Products ---" -ForegroundColor Cyan

        Write-Host "  Antivirus Products:" -ForegroundColor White
        foreach ($p in $av) {
            # productState hex: bits 12-19 = enabled, bits 4-11 = up-to-date
            $state = [Convert]::ToString($p.productState, 16).PadLeft(6, '0')
            $enabled = $state.Substring(1,2) -eq "10"
            $upToDate = $state.Substring(3,2) -eq "00"
            Write-Host ("    {0,-40} Enabled={1,-6} UpToDate={2}" -f $p.displayName, $enabled, $upToDate) -ForegroundColor Gray
            Write-Log "AV Product: $($p.displayName) | Enabled=$enabled | UpToDate=$upToDate" "INFO"
        }

        Write-Host "  Firewall Products:" -ForegroundColor White
        foreach ($p in $fw) {
            Write-Host "    $($p.displayName)" -ForegroundColor Gray
            Write-Log "Firewall Product: $($p.displayName)" "INFO"
        }

        Write-Host "  Antispyware Products:" -ForegroundColor White
        foreach ($p in $as) {
            Write-Host "    $($p.displayName)" -ForegroundColor Gray
            Write-Log "Antispyware Product: $($p.displayName)" "INFO"
        }
        Write-Host ""
    } catch {
        Write-Log "Failed to query Security Center 2 (non-fatal): $_" "WARNING"
    }
}

$mpStatus = Get-DefenderStatus
Get-SecurityCenterStatus

# ==============================================================================
# STEP 2: Set registry keys to enable protections / remove blocking entries
# ==============================================================================
Write-Log "==============================" "INFO"
Write-Log "STEP 2: Applying registry fixes to enable Windows Security..." "INFO"
Write-Log "==============================" "INFO"

$registryFixes = @(
    # Enable Windows Defender
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender";                        Name = "DisableAntiSpyware";        Value = 0; Type = "DWord"; Desc = "Re-enable Defender (DisableAntiSpyware=0)" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender";                        Name = "DisableAntiVirus";          Value = 0; Type = "DWord"; Desc = "Re-enable Antivirus (DisableAntiVirus=0)" },

    # Real-Time Protection
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection";   Name = "DisableRealtimeMonitoring"; Value = 0; Type = "DWord"; Desc = "Enable Real-Time Monitoring" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection";   Name = "DisableBehaviorMonitoring"; Value = 0; Type = "DWord"; Desc = "Enable Behavior Monitoring" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection";   Name = "DisableIOAVProtection";     Value = 0; Type = "DWord"; Desc = "Enable IOAV (download) Protection" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection";   Name = "DisableOnAccessProtection"; Value = 0; Type = "DWord"; Desc = "Enable On-Access Protection" },

    # Ensure Defender service is not blocked via registry
    @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend";                         Name = "Start";                     Value = 2; Type = "DWord"; Desc = "Set WinDefend service start to Automatic" },
    @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Services\SecurityHealthService";             Name = "Start";                     Value = 2; Type = "DWord"; Desc = "Set SecurityHealthService start to Automatic" },

    # Windows Security Center / System Tray
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";                       Name = "SecurityHealth";            Value = "%windir%\system32\SecurityHealthSystray.exe"; Type = "ExpandString"; Desc = "Restore Security Health systray entry" },

    # Enable Windows Security App (wasnt launched by policies)
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\App and Browser protection"; Name = "UILockdown"; Value = 0; Type = "DWord"; Desc = "Unlock Security Center App & Browser UI" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications";              Name = "DisableNotifications"; Value = 0; Type = "DWord"; Desc = "Enable Security Center Notifications" }
)

foreach ($fix in $registryFixes) {
    try {
        # Create the key path if it doesn't exist
        if (-not (Test-Path $fix.Path)) {
            New-Item -Path $fix.Path -Force | Out-Null
            Write-Log "Created registry path: $($fix.Path)" "INFO"
        }

        # Read current value for before/after comparison
        $current = $null
        try { $current = (Get-ItemProperty -Path $fix.Path -Name $fix.Name -ErrorAction Stop).$($fix.Name) } catch {}

        Set-ItemProperty -Path $fix.Path -Name $fix.Name -Value $fix.Value -Type $fix.Type -Force -ErrorAction Stop
        Write-Log "[$($fix.Desc)] Set $($fix.Name) = $($fix.Value) (was: $current)" "SUCCESS"
    } catch {
        Write-Log "Failed to apply fix [$($fix.Desc)]: $_" "WARNING"
    }
}

# Remove known DisableAntiSpyware if set to 1 (group policy remnant)
$gpDefenderPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
try {
    $daspVal = (Get-ItemProperty -Path $gpDefenderPath -Name "DisableAntiSpyware" -ErrorAction SilentlyContinue).DisableAntiSpyware
    if ($daspVal -eq 1) {
        Remove-ItemProperty -Path $gpDefenderPath -Name "DisableAntiSpyware" -Force -ErrorAction Stop
        Write-Log "Removed blocking GPO key DisableAntiSpyware from $gpDefenderPath" "SUCCESS"
    }
} catch {
    Write-Log "Could not remove DisableAntiSpyware key (may not exist, which is fine): $_" "INFO"
}

# Restart relevant services
Write-Log "Restarting Windows Security services..." "INFO"
$services = @("WinDefend", "SecurityHealthService", "wscsvc", "Sense")
foreach ($svc in $services) {
    try {
        $s = Get-Service -Name $svc -ErrorAction Stop
        if ($s.Status -ne "Running") {
            Start-Service -Name $svc -ErrorAction Stop
            Write-Log "Started service: $svc" "SUCCESS"
        } else {
            Restart-Service -Name $svc -Force -ErrorAction Stop
            Write-Log "Restarted service: $svc" "SUCCESS"
        }
    } catch {
        Write-Log "Could not start/restart service '$svc' (may not exist on this SKU): $_" "WARNING"
    }
}

# Update Defender signatures
Write-Log "Attempting to update Windows Defender signatures..." "INFO"
try {
    Update-MpSignature -ErrorAction Stop
    Write-Log "Defender signatures updated successfully." "SUCCESS"
} catch {
    Write-Log "Signature update failed (offline or service issue): $_" "WARNING"
}

# ==============================================================================
# STEP 3: Prompt user to verify Windows Security is working
# ==============================================================================
Write-Log "==============================" "INFO"
Write-Log "STEP 3: User verification..." "INFO"
Write-Log "==============================" "INFO"

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host " ACTION REQUIRED: Please verify Windows Security is working." -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host @"
  1. Open the Start Menu and search for 'Windows Security'
  2. Launch the app and check that the following show green checkmarks:
       - Virus & threat protection
       - Firewall & network protection
       - App & browser control
  3. If the app opens normally and shows no red warnings, security is restored.
"@ -ForegroundColor White

$verified = $false
while (-not $verified) {
    $response = Read-Host "`nIs Windows Security now working correctly? (yes/no)"
    switch ($response.Trim().ToLower()) {
        { $_ -in "yes", "y" } {
            Write-Log "User confirmed Windows Security is working." "SUCCESS"
            Write-Host "`n[SUCCESS] Great! Windows Security has been restored." -ForegroundColor Green
            $verified = $true
        }
        { $_ -in "no", "n" } {
            Write-Log "User reported Windows Security is still not working. Proceeding to manual install step." "WARNING"
            Write-Host "`n[INFO] Proceeding to manual installation steps..." -ForegroundColor Yellow
            $verified = $true  # Exit loop, fall through to Step 4
        }
        default {
            Write-Host "  Please enter 'yes' or 'no'." -ForegroundColor Yellow
        }
    }
}

# ==============================================================================
# STEP 4: Manual installation instructions (if security still not working)
# ==============================================================================
if ($response.Trim().ToLower() -in "no", "n") {
    Write-Log "==============================" "INFO"
    Write-Log "STEP 4: Manual Windows Security installation guide..." "INFO"
    Write-Log "==============================" "INFO"

    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host " MANUAL REPAIR: Windows Security App Installation" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host @"
  Automated fixes were insufficient. Follow these steps manually:

  --- Option A: Re-register via PowerShell (run in an elevated window) ---
    Get-AppxPackage -AllUsers Microsoft.SecHealthUI | Remove-AppxPackage
    Get-AppxPackage -AllUsers *SecHealthUI* | Remove-AppxPackage -ErrorAction SilentlyContinue
    Add-AppxPackage -Register -DisableDevelopmentMode "C:\Windows\SystemApps\Microsoft.Windows.SecHealthUI_cw5n1h2txyewy\AppXManifest.xml"

  --- Option B: DISM Health Restore ---
    DISM /Online /Cleanup-Image /RestoreHealth
    sfc /scannow

  --- Option C: Windows Security Reset via wsreset ---
    wsreset.exe

  --- Option D: Microsoft Official Support Guide ---
    Reference:
    https://learn.microsoft.com/en-us/answers/questions/5563559/windows-security-is-missing-and-incomplete-from-my

"@ -ForegroundColor White

    Write-Log "Manual installation instructions displayed to user." "INFO"

    # Attempt Option A automatically
    $attemptAuto = Read-Host "Would you like this script to attempt Option A (re-register SecHealthUI) automatically? (yes/no)"
    if ($attemptAuto.Trim().ToLower() -in "yes", "y") {
        Write-Log "Attempting automatic re-registration of Microsoft.SecHealthUI..." "INFO"
        try {
            Get-AppxPackage -AllUsers "Microsoft.SecHealthUI" -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
            $manifestPath = "C:\Windows\SystemApps\Microsoft.Windows.SecHealthUI_cw5n1h2txyewy\AppXManifest.xml"
            if (Test-Path $manifestPath) {
                Add-AppxPackage -Register -DisableDevelopmentMode $manifestPath -ErrorAction Stop
                Write-Log "SecHealthUI re-registered successfully. Please reboot and recheck." "SUCCESS"
                Write-Host "`n[SUCCESS] SecHealthUI re-registered. Reboot your machine and check Windows Security again." -ForegroundColor Green
            } else {
                Write-Log "AppXManifest.xml not found at expected path: $manifestPath" "ERROR"
                Write-Host "`n[ERROR] Manifest not found. You may need to run DISM /RestoreHealth first (Option B)." -ForegroundColor Red
            }
        } catch {
            Write-Log "Auto re-registration failed: $_" "ERROR"
            Write-Host "`n[ERROR] Re-registration failed. Please follow the manual steps above." -ForegroundColor Red
        }

        # Attempt Option B (SFC + DISM)
        Write-Log "Running SFC and DISM health restore..." "INFO"
        Write-Host "`n[INFO] Running 'sfc /scannow' (this may take several minutes)..." -ForegroundColor Cyan
        Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -Wait -NoNewWindow
        Write-Log "SFC scan complete." "INFO"

        Write-Host "[INFO] Running 'DISM /RestoreHealth' (this may take several minutes)..." -ForegroundColor Cyan
        Start-Process -FilePath "DISM.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth" -Wait -NoNewWindow
        Write-Log "DISM RestoreHealth complete." "INFO"
    } else {
        Write-Log "User opted to follow manual steps themselves." "INFO"
    }

    Write-Host "`n[NEXT STEP] After completing manual steps, reboot and run this script again to verify." -ForegroundColor Yellow
    Write-Log "Script completed. Manual intervention required." "WARNING"
} else {
    Write-Log "Script completed successfully. No manual intervention needed." "SUCCESS"
}

Write-Log "==============================" "INFO"
Write-Log "Log saved to: $LogFile" "INFO"
Write-Host "`n[LOG] Full log saved to: $LogFile" -ForegroundColor Cyan