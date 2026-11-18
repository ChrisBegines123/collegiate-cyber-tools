#Requires -RunAsAdministrator
# CCDC26 - Comprehensive Persistence Hunter
# Adapted from Hunt-Persistence.ps1 with inlined dependencies.
# Can source lib/common.ps1 if available, otherwise self-sufficient.

param(
    [switch]$Quick,
    [switch]$Full,
    [string]$OutputFile,
    [ValidateSet("Registry","ScheduledTasks","WMI","Services","Startup",
                 "DLLHijacking","COM","SSP","PrintMonitors","NetworkProviders",
                 "PowerShellProfile","BitsJobs","ADBackdoors")]
    [string]$Category,
    [switch]$Remediate
)

$ErrorActionPreference = "Continue"

$LogDir = "C:\ccdc26\logs"
$BackupDir = "C:\ccdc26\backups"
$QuarantineDir = "C:\ccdc26\quarantine"
@($LogDir, $BackupDir, $QuarantineDir) | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
}

# Try sourcing lib/common.ps1 for richer output
$libPath = Join-Path $PSScriptRoot "lib\common.ps1"
if (Test-Path $libPath) {
    . $libPath
} else {
    function Info    { param([string]$M) Write-Host "[INFO] $M" -ForegroundColor Blue }
    function Success { param([string]$M) Write-Host "[OK]   $M" -ForegroundColor Green }
    function Warn    { param([string]$M) Write-Host "[WARN] $M" -ForegroundColor Yellow }
    function Error   { param([string]$M) Write-Host "[ERR]  $M" -ForegroundColor Red }
    function Header  { param([string]$M) Write-Host "`n=== $M ===" -ForegroundColor Magenta; Write-Host "" }
    function Finding { param([string]$M) Write-Host "[FINDING] $M" -ForegroundColor Red }
    function Log-Action  { param([string]$M) "$((Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) - $M" | Out-File "$LogDir\actions.log" -Append -Encoding UTF8 }
    function Log-Finding { param([string]$M) "$((Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) - $M" | Out-File "$LogDir\findings.log" -Append -Encoding UTF8; Finding $M }
    function Require-Administrator {
        $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Write-Host "[ERR] Run as Administrator" -ForegroundColor Red; exit 1 }
    }
    function Backup-RegistryKey { param([string]$KeyPath, [string]$Description)
        $ts = Get-Date -Format "yyyyMMdd_HHmmss"; $safe = $KeyPath -replace '[\\:]','_'
        reg export $KeyPath "$BackupDir\reg_${safe}_${ts}.reg" /y 2>$null | Out-Null
    }
    function Prompt-YesNo { param([string]$Message, [bool]$Default=$false)
        $r = Read-Host "$Message [y/N]"
        return ($r -ieq 'y' -or $r -ieq 'yes')
    }
}

Require-Administrator

$OSInfo = @{
    IsDomainController = $false
    Caption = (Get-CimInstance Win32_OperatingSystem).Caption
    ComputerName = $env:COMPUTERNAME
    DomainName = (Get-CimInstance Win32_ComputerSystem).Domain
}
try { $OSInfo.IsDomainController = (Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4 } catch {}

$script:TotalFindings = 0
$script:FindingsByCategory = @{}
$script:HighRiskFindings = [System.Collections.ArrayList]::new()

function Add-Finding {
    param([string]$Category, [string]$Description, [string]$Path, [string]$Value,
          [ValidateSet("Low","Medium","High","Critical")][string]$Risk = "Medium",
          [hashtable]$RemediationInfo = $null)
    $script:TotalFindings++
    if (-not $script:FindingsByCategory.ContainsKey($Category)) { $script:FindingsByCategory[$Category] = 0 }
    $script:FindingsByCategory[$Category]++
    Finding "$Description"
    Write-Host "      Path:  $Path" -ForegroundColor Gray
    if ($Value) { Write-Host "      Value: $Value" -ForegroundColor Gray }
    Write-Host "      Risk:  $Risk" -ForegroundColor $(switch($Risk){"Low"{"Gray"}"Medium"{"Yellow"}"High"{"Red"}"Critical"{"DarkRed"}})
    Log-Finding "[$Risk] $Category - $Description | Path: $Path | Value: $Value"
    if ($Risk -in @("High","Critical") -and $RemediationInfo) {
        $null = $script:HighRiskFindings.Add(@{Category=$Category;Description=$Description;Path=$Path;Value=$Value;Risk=$Risk;Remediation=$RemediationInfo})
    }
    if ($OutputFile) { "[$Risk] $Category - $Description | Path: $Path | Value: $Value" | Out-File $OutputFile -Append -Encoding UTF8 }
}

function Test-SuspiciousPath { param([string]$P)
    if (-not $P) { return $false }
    $patterns = @([regex]::Escape($env:TEMP),[regex]::Escape($env:TMP),'\\AppData\\Local\\Temp\\','\\Users\\Public\\','\\ProgramData\\','\\Recycle','\\Windows\\Temp\\')
    foreach ($pat in $patterns) { if ($P -match $pat) { return $true } }
    return $false
}

# ── Category functions (same logic as Hunt-Persistence.ps1) ──

function Hunt-RegistryPersistence {
    Header "Registry Run Key Persistence"
    $runKeys = @(
        @{Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";Desc="HKLM Run"},
        @{Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce";Desc="HKLM RunOnce"},
        @{Path="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";Desc="HKCU Run"},
        @{Path="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce";Desc="HKCU RunOnce"}
    )
    foreach ($key in $runKeys) {
        if (Test-Path $key.Path) {
            $props = Get-ItemProperty -Path $key.Path -ErrorAction SilentlyContinue
            $names = $props.PSObject.Properties | Where-Object { $_.Name -notin @('PSPath','PSParentPath','PSChildName','PSDrive','PSProvider') }
            foreach ($prop in $names) {
                $risk = if (Test-SuspiciousPath $prop.Value) { "High" } else { "Medium" }
                Add-Finding -Category "Registry" -Description "$($key.Desc): $($prop.Name)" -Path $key.Path -Value $prop.Value -Risk $risk `
                    -RemediationInfo @{Type="RegistryValue";Key=$key.Path;Name=$prop.Name}
            }
        }
    }
    # Winlogon
    $wl = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    if (Test-Path $wl) {
        $shell = (Get-ItemProperty $wl -ErrorAction SilentlyContinue).Shell
        if ($shell -and $shell -ne "explorer.exe") {
            Add-Finding -Category "Registry" -Description "Winlogon Shell modified" -Path $wl -Value "Shell=$shell" -Risk "Critical" `
                -RemediationInfo @{Type="RegistryValue";Key=$wl;Name="Shell";RestoreValue="explorer.exe"}
        }
        $ui = (Get-ItemProperty $wl -ErrorAction SilentlyContinue).Userinit
        if ($ui -and $ui -ne "C:\Windows\system32\userinit.exe," -and $ui -ne "C:\Windows\system32\userinit.exe") {
            Add-Finding -Category "Registry" -Description "Winlogon Userinit modified" -Path $wl -Value "Userinit=$ui" -Risk "Critical" `
                -RemediationInfo @{Type="RegistryValue";Key=$wl;Name="Userinit";RestoreValue="C:\Windows\system32\userinit.exe,"}
        }
    }
    # AppInit_DLLs
    $wp = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows"
    if (Test-Path $wp) {
        $ai = (Get-ItemProperty $wp -ErrorAction SilentlyContinue).AppInit_DLLs
        if ($ai -and $ai.Trim() -ne "") {
            Add-Finding -Category "Registry" -Description "AppInit_DLLs set" -Path $wp -Value $ai -Risk "Critical" `
                -RemediationInfo @{Type="RegistryValue";Key=$wp;Name="AppInit_DLLs";RestoreValue=""}
        }
    }
}

function Hunt-ScheduledTasks {
    Header "Scheduled Task Persistence"
    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue
    if (-not $tasks) { return }
    $suspBins = @('powershell','pwsh','cmd','wscript','cscript','mshta','regsvr32','rundll32','certutil','bitsadmin')
    $flagged = 0
    foreach ($task in $tasks) {
        $reasons = @()
        foreach ($a in $task.Actions) {
            $exe = if ($a.Execute) { $a.Execute } else { "" }
            foreach ($b in $suspBins) { if ($exe -match [regex]::Escape($b)) { $reasons += "Runs $b"; break } }
            if (Test-SuspiciousPath $exe) { $reasons += "Suspicious path" }
        }
        $principal = $task.Principal
        if ($principal -and $principal.UserId -match 'SYSTEM' -and $task.TaskPath -notmatch '\\Microsoft\\') { $reasons += "SYSTEM non-Microsoft" }
        if ($reasons.Count -gt 0) {
            $flagged++
            $acts = ($task.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join " | "
            $risk = if ($reasons -match "SYSTEM|Suspicious") { "High" } else { "Medium" }
            Add-Finding -Category "ScheduledTasks" -Description "Suspicious: $($task.TaskPath)$($task.TaskName)" -Path $task.TaskPath -Value $acts -Risk $risk `
                -RemediationInfo @{Type="ScheduledTask";TaskName=$task.TaskName;TaskPath=$task.TaskPath}
        }
    }
    if ($flagged -eq 0) { Success "No suspicious scheduled tasks" }
}

function Hunt-WMIPersistence {
    Header "WMI Event Subscription Persistence"
    $found = 0
    foreach ($cls in @("__EventFilter","__EventConsumer","__FilterToConsumerBinding")) {
        try {
            $items = Get-WmiObject -Namespace root\Subscription -Class $cls -ErrorAction Stop
            foreach ($item in $items) { $found++; Add-Finding -Category "WMI" -Description "WMI $cls found" -Path "root\Subscription" -Value ($item | Out-String).Trim() -Risk "Critical" }
        } catch {}
    }
    if ($found -eq 0) { Success "No WMI event subscriptions" }
}

function Hunt-ServicePersistence {
    Header "Service Persistence"
    $svcs = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue
    $legit = @('C:\Windows\','C:\Program Files\','C:\Program Files (x86)\')
    $flagged = 0
    foreach ($svc in $svcs) {
        $bp = $svc.PathName; if (-not $bp) { continue }
        $reasons = @()
        $isLeg = $false; foreach ($l in $legit) { if ($bp -match [regex]::Escape($l)) { $isLeg = $true; break } }
        if (-not $isLeg -and $bp -notmatch 'svchost\.exe' -and $bp -notmatch '^"?C:\\Windows\\') { $reasons += "Unusual path" }
        if ($bp -notmatch '^"' -and $bp -match ' ' -and $bp -match '\\[^\\]+\\') { $reasons += "Unquoted" }
        if ($svc.StartName -match 'LocalSystem' -and -not $isLeg) { $reasons += "SYSTEM unusual" }
        if ($reasons.Count -gt 0) {
            $flagged++; $risk = if ($reasons -match "Unusual|SYSTEM") { "High" } else { "Medium" }
            Add-Finding -Category "Services" -Description "Service: $($svc.Name)" -Path $bp -Value "Display=$($svc.DisplayName) Start=$($svc.StartMode) RunAs=$($svc.StartName)" -Risk $risk
        }
    }
    if ($flagged -eq 0) { Success "No suspicious services" }
}

function Hunt-StartupFolders {
    Header "Startup Folder Persistence"
    $paths = @("C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup")
    Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $paths += Join-Path $_.FullName "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
    }
    $found = 0
    foreach ($p in $paths) {
        if (Test-Path $p) {
            Get-ChildItem $p -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "desktop.ini" } | ForEach-Object {
                $found++; Add-Finding -Category "Startup" -Description "Startup item: $($_.Name)" -Path $_.FullName -Value "Size=$($_.Length)" -Risk "High"
            }
        }
    }
    if ($found -eq 0) { Success "No startup folder items" }
}

function Hunt-DLLHijacking {
    Header "DLL Hijacking / IFEO"
    $ifeo = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
    $flagged = 0
    if (Test-Path $ifeo) {
        Get-ChildItem $ifeo -ErrorAction SilentlyContinue | ForEach-Object {
            $dbg = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).Debugger
            if ($dbg) { $flagged++; Add-Finding -Category "DLLHijacking" -Description "IFEO Debugger on $($_.PSChildName)" -Path $_.PSPath -Value "Debugger=$dbg" -Risk "High" }
        }
    }
    if ($flagged -eq 0) { Success "No IFEO persistence" }
}

function Hunt-COMHijacking {
    Header "COM Object Hijacking"
    $hkcu = "HKCU:\SOFTWARE\Classes\CLSID"; $flagged = 0
    if (Test-Path $hkcu) {
        Get-ChildItem $hkcu -ErrorAction SilentlyContinue | ForEach-Object {
            $ip = Join-Path $_.PSPath "InprocServer32"
            if (Test-Path $ip) {
                $dll = (Get-ItemProperty $ip -ErrorAction SilentlyContinue).'(default)'
                if ($dll) { $flagged++; Add-Finding -Category "COM" -Description "HKCU COM override: $($_.PSChildName)" -Path $ip -Value $dll -Risk "High" }
            }
        }
    }
    if ($flagged -eq 0) { Success "No COM hijacking" }
}

function Hunt-SSPPersistence {
    Header "Security Support Providers"
    $expected = @('kerberos','msv1_0','schannel','wdigest','tspkg','pku2u','cloudAP','')
    $flagged = 0
    $lsaP = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
    if (Test-Path $lsaP) {
        $pkgs = (Get-ItemProperty $lsaP -ErrorAction SilentlyContinue).'Security Packages'
        if ($pkgs) { foreach ($p in $pkgs) { if ($p.Trim().ToLower() -ne "" -and $p.Trim().ToLower() -notin $expected) { $flagged++; Add-Finding -Category "SSP" -Description "Unknown SSP: $p" -Path $lsaP -Value $p -Risk "Critical" } } }
    }
    if ($flagged -eq 0) { Success "SSPs look clean" }
}

function Hunt-PrintMonitors {
    Header "Print Monitor Persistence"
    $mp = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors"
    $known = @('Local Port','Standard TCP/IP Port','USB Monitor','WSD Port','Microsoft Shared Fax Monitor','Appmon')
    $flagged = 0
    if (Test-Path $mp) {
        Get-ChildItem $mp -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.PSChildName -notin $known) { $flagged++; $drv = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).Driver; Add-Finding -Category "PrintMonitors" -Description "Unknown monitor: $($_.PSChildName)" -Path $_.PSPath -Value "Driver=$drv" -Risk "High" }
        }
    }
    if ($flagged -eq 0) { Success "Print monitors clean" }
}

function Hunt-NetworkProviders {
    Header "Network Provider DLLs"
    $op = "HKLM:\SYSTEM\CurrentControlSet\Control\NetworkProvider\Order"; $flagged = 0
    if (Test-Path $op) {
        $order = (Get-ItemProperty $op -ErrorAction SilentlyContinue).ProviderOrder
        if ($order) {
            foreach ($prov in ($order -split ',')) {
                $prov = $prov.Trim()
                $pk = "HKLM:\SYSTEM\CurrentControlSet\Services\$prov\NetworkProvider"
                if (Test-Path $pk) {
                    $pp = (Get-ItemProperty $pk -ErrorAction SilentlyContinue).ProviderPath
                    if ($pp -and (Test-SuspiciousPath $pp)) { $flagged++; Add-Finding -Category "NetworkProviders" -Description "Suspicious provider: $prov" -Path $pk -Value "ProviderPath=$pp" -Risk "Critical" }
                }
            }
        }
    }
    if ($flagged -eq 0) { Success "Network providers clean" }
}

function Hunt-PowerShellProfile {
    Header "PowerShell Profile Persistence"
    $profiles = @(
        @{Path="$PSHOME\Profile.ps1";Desc="AllUsers AllHosts"},
        @{Path="$PSHOME\Microsoft.PowerShell_profile.ps1";Desc="AllUsers CurrentHost"}
    )
    Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $profiles += @{Path="$($_.FullName)\Documents\WindowsPowerShell\Profile.ps1";Desc="$($_.Name) PS5"}
        $profiles += @{Path="$($_.FullName)\Documents\PowerShell\Profile.ps1";Desc="$($_.Name) PS7"}
    }
    $found = 0
    foreach ($p in $profiles) {
        if (Test-Path $p.Path) {
            $c = Get-Content $p.Path -Raw -ErrorAction SilentlyContinue
            if ($c -and $c.Trim() -ne "") { $found++; Add-Finding -Category "PowerShellProfile" -Description "PS profile: $($p.Desc)" -Path $p.Path -Value "Lines=$(($c -split "`n").Count)" -Risk "High" }
        }
    }
    if ($found -eq 0) { Success "No PS profiles" }
}

function Hunt-BitsJobs {
    Header "BITS Transfer Jobs"
    $flagged = 0
    try {
        Import-Module BitsTransfer -ErrorAction SilentlyContinue
        Get-BitsTransfer -AllUsers -ErrorAction Stop | ForEach-Object {
            $flagged++; Add-Finding -Category "BitsJobs" -Description "BITS Job: $($_.DisplayName)" -Path "BITS" -Value "Owner=$($_.OwnerAccount) State=$($_.JobState)" -Risk "High"
        }
    } catch {}
    if ($flagged -eq 0) { Success "No BITS jobs" }
}

function Hunt-ADBackdoors {
    Header "AD Backdoor Detection"
    try { $isDC = (Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4 } catch { $isDC = $false }
    if (-not $isDC) { Info "Not a DC, skipping"; return }
    try { Import-Module ActiveDirectory -ErrorAction Stop } catch { Warn "AD module unavailable"; return }
    $users = Get-ADUser -Filter * -Properties AdminCount, Created, Enabled, LastLogonDate, SamAccountName, MemberOf -ErrorAction SilentlyContinue
    if (-not $users -or $users.Count -lt 3) { return }
    Info "Analyzing $($users.Count) AD users..."
    $flagged = 0
    foreach ($u in $users) {
        $reasons = @()
        if ($u.SamAccountName -match '^[a-z0-9]{16,}$' -or $u.SamAccountName -match '^\$' -or $u.SamAccountName -match '^(admin|test|temp|backdoor|hack|svc_)') { $reasons += "Suspicious name" }
        if ($u.Enabled -and -not $u.LastLogonDate -and $u.Created -lt (Get-Date).AddDays(-1)) { $reasons += "Enabled no logon" }
        if ($u.AdminCount -eq 1) {
            $adminGroups = @('Domain Admins','Enterprise Admins','Schema Admins','Administrators')
            $inAdmin = $false; foreach ($g in $u.MemberOf) { if (($g -split ',')[0] -replace '^CN=','' -in $adminGroups) { $inAdmin = $true; break } }
            if (-not $inAdmin) { $reasons += "Orphaned AdminCount" }
        }
        if ($u.Created -gt (Get-Date).AddDays(-7)) { $reasons += "Created <7d" }
        if ($reasons.Count -gt 0) {
            $flagged++; $risk = if ($reasons.Count -ge 2) { "High" } else { "Medium" }
            Add-Finding -Category "ADBackdoors" -Description "Anomalous: $($u.SamAccountName) [$($reasons -join '; ')]" -Path "AD:$($u.DistinguishedName)" -Value "Enabled=$($u.Enabled) Created=$($u.Created)" -Risk $risk
        }
    }
    if ($flagged -eq 0) { Success "No anomalous AD accounts" }
}

# ── Execution ──
Header "CCDC26 Persistence Hunter"
Write-Host "OS: $($OSInfo.Caption)" -ForegroundColor Gray
Write-Host "Computer: $($OSInfo.ComputerName)" -ForegroundColor Gray
if ($OutputFile) { "=== CCDC26 Persistence Hunt - $(Get-Date) ===" | Out-File $OutputFile -Encoding UTF8 }

$startTime = Get-Date

$allChecks = @(
    @{Name="Registry";Fn={Hunt-RegistryPersistence}}, @{Name="ScheduledTasks";Fn={Hunt-ScheduledTasks}},
    @{Name="WMI";Fn={Hunt-WMIPersistence}}, @{Name="Services";Fn={Hunt-ServicePersistence}},
    @{Name="Startup";Fn={Hunt-StartupFolders}}, @{Name="DLLHijacking";Fn={Hunt-DLLHijacking}},
    @{Name="COM";Fn={Hunt-COMHijacking}}, @{Name="SSP";Fn={Hunt-SSPPersistence}},
    @{Name="PrintMonitors";Fn={Hunt-PrintMonitors}}, @{Name="NetworkProviders";Fn={Hunt-NetworkProviders}},
    @{Name="PowerShellProfile";Fn={Hunt-PowerShellProfile}}, @{Name="BitsJobs";Fn={Hunt-BitsJobs}},
    @{Name="ADBackdoors";Fn={Hunt-ADBackdoors}}
)

if ($Category) {
    $check = $allChecks | Where-Object { $_.Name -eq $Category }
    if ($check) { & $check.Fn } else { Error "Unknown category: $Category" }
} elseif ($Quick -or $Full) {
    foreach ($c in $allChecks) { try { & $c.Fn } catch { Error "$($c.Name) failed: $_" } }
} else {
    foreach ($c in $allChecks) { try { & $c.Fn } catch { Error "$($c.Name) failed: $_" } }
}

$duration = ((Get-Date) - $startTime).TotalSeconds
Header "Hunt Summary"
if ($script:TotalFindings -eq 0) { Success "No findings" }
else {
    Warn "$($script:TotalFindings) finding(s):"
    foreach ($cat in $script:FindingsByCategory.GetEnumerator() | Sort-Object Value -Descending) {
        Write-Host "    $($cat.Value) - $($cat.Key)" -ForegroundColor Yellow
    }
    Write-Host "  High/Critical: $($script:HighRiskFindings.Count)" -ForegroundColor Red
}
Info "Completed in $([math]::Round($duration, 1))s"
Log-Action "Persistence hunt: $($script:TotalFindings) findings in $([math]::Round($duration,1))s"
