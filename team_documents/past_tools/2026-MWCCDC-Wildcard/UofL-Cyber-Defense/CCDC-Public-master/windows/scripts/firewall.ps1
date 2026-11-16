# ----
# Logging
# ----
$LogDir = "C:\Logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
$TimestampName = Get-Date -Format "HHmm"
$LogFile = Join-Path $LogDir "Firewall_$TimestampName.log"

Start-Transcript -Path $LogFile

# ----
# Status Function
# ----
function Write-Status {
 param (
    [Parameter(Mandatory)]
    [string]$Message,

    [ValidateSet("Info","Success","Warning","Error")]
    [string]$Level = "Info"
 ) 
 
 $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
 $LogEntry = "$Timestamp [$Level] $Message"

 switch ($Level) {
    "Success" { Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
    "Warning" { Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
    "Error"   { Write-Host "[ERROR] $Message"   -ForegroundColor Red }
    default   { Write-Host "[INFO] $Message" }
 }
}

# ----
# Detects Joined Domain
# ----
$DomainJoined = $false
if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain -or $ADAvailable) {
    $Domain = (Get-CimInstance Win32_ComputerSystem).Domain
    $SysVol = "\\$Domain\SYSVOL\$Domain"
    Write-Status "Domain '$Domain' Detected" "Success"
    $DomainJoined = $true
} else {
    Write-Status "Machine is not domain-joined" "Warning"
}

# ----
# Detect scored services present on THIS Windows machine
# Checks: FTP, SMTP, DNS, HTTP (IIS), AD DS
# ----
function Test-ServicePresent {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Test,
        [string]$Hint = ""
    )

    try {
        $present = & $Test

        if ($present) {
            Write-Status "${Name}: PRESENT $Hint" "Success"
        }
        else {
            Write-Status "${Name}: NOT present $Hint" "Warning"
        }

        return [bool]$present
    }
    catch {
        Write-Status "${Name}: ERROR while checking - $($_.Exception.Message)" "Error"
        return $false
    }
}

# ----
# Service executable info (Services.msc Path to executable)
# Uses CIM when available, otherwise falls back to registry ImagePath.
# ----
function Get-ServiceExecutableInfo {
    param(
        [Parameter(Mandatory)][string]$ServiceName
    )

    $svcBasic = Get-Service -Name $ServiceName -ErrorAction Stop

    $cim = $null
    try {
        $cim = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
        if (-not $cim) { $cim = $null }
    } catch {
        $cim = $null
    }

    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
    $imagePath  = $null
    $startValue = $null
    $objName    = $null

    if (Test-Path $regPath) {
        try {
            $p = Get-ItemProperty -Path $regPath -ErrorAction Stop
            $imagePath  = $p.ImagePath
            $startValue = $p.Start
            $objName    = $p.ObjectName
        } catch { }
    }

    $rawPath = $null
    if ($cim -and $cim.PathName) {
        $rawPath = $cim.PathName
    } elseif ($imagePath) {
        $rawPath = $imagePath
    }

    $exePath = $null
    if (-not [string]::IsNullOrWhiteSpace($rawPath)) {
        $trim = $rawPath.Trim()
        if ($trim.StartsWith('"')) {
            $exePath = ($trim -split '"', 3)[1]
        } else {
            $exePath = ($trim -split '\s+', 2)[0]
        }
        if ($exePath) { $exePath = [Environment]::ExpandEnvironmentVariables($exePath) }
    }

    $exeDir = $null
    if ($exePath) {
        try { $exeDir = Split-Path -Parent $exePath } catch { $exeDir = $null }
    }

    $startMode = $null
    if ($cim -and $cim.StartMode) {
        $startMode = $cim.StartMode
    } elseif ($startValue -ne $null) {
        $startMode = switch ($startValue) {
            0 { "Boot" }
            1 { "System" }
            2 { "Auto" }
            3 { "Manual" }
            4 { "Disabled" }
            default { "Unknown($startValue)" }
        }
    }

    $startName = $null
    if ($cim -and $cim.StartName) {
        $startName = $cim.StartName
    } elseif ($objName) {
        $startName = $objName
    }

    [pscustomobject]@{
        ServiceName    = $svcBasic.Name
        DisplayName    = $svcBasic.DisplayName
        Status         = $svcBasic.Status
        StartMode      = $startMode
        StartName      = $startName
        PathNameRaw    = $rawPath
        ExecutablePath = $exePath
        ExecutableDir  = $exeDir
        RegistryKey    = $regPath
    }
}

function Log-ServiceExecutableInfo {
    param(
        [Parameter(Mandatory)][string]$NameForLog,
        [Parameter(Mandatory)][string]$ServiceName
    )

    $s = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $s) { return $null }

    try {
        $info = Get-ServiceExecutableInfo -ServiceName $ServiceName

        Write-Status "${NameForLog}: Service detected ($ServiceName)" "Success"
        Write-Status "${NameForLog}: DisplayName='$($info.DisplayName)' Status=$($info.Status) StartMode=$($info.StartMode) Account=$($info.StartName)" "Info"
        Write-Status "${NameForLog}: PathName (Services.msc) = $($info.PathNameRaw)" "Info"
        Write-Status "${NameForLog}: Executable = $($info.ExecutablePath)" "Info"
        Write-Status "${NameForLog}: Executable directory = $($info.ExecutableDir)" "Info"
        Write-Status "${NameForLog}: Service registry key = $($info.RegistryKey)" "Info"

        return $info
    }
    catch {
        Write-Status "${NameForLog}: Failed to read service executable info for '$ServiceName' - $($_.Exception.Message)" "Error"
        return $null
    }
}

# ----
# If a service is Stopped, attempt to start it and verify.
# Logs ERROR if it fails to reach Running.
# ----
function Ensure-ServiceRunning {
    param(
        [Parameter(Mandatory)][string]$NameForLog,
        [Parameter(Mandatory)][string]$ServiceName,
        [int]$TimeoutSeconds = 20
    )

    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Status "${NameForLog}: Service '$ServiceName' not present; cannot start." "Warning"
        return $false
    }

    function Get-RefreshedService { Get-Service -Name $ServiceName -ErrorAction SilentlyContinue }

    $svc = Get-RefreshedService
    if ($svc.Status -eq 'Running') {
        Write-Status "${NameForLog}: Service is already Running." "Success"
        return $true
    }

    if ($svc.Status -eq 'Stopped') {
        Write-Status "${NameForLog}: Service is Stopped. Attempting to start..." "Warning"

        try {
            Start-Service -Name $ServiceName -ErrorAction Stop
        }
        catch {
            Write-Status "${NameForLog}: Start-Service threw an error: $($_.Exception.Message)" "Error"
            return $false
        }

        try {
            $svc = Get-RefreshedService
            if ($svc) { $svc.WaitForStatus('Running', [TimeSpan]::FromSeconds($TimeoutSeconds)) | Out-Null }
        } catch { }

        $svc = Get-RefreshedService
        if ($svc -and $svc.Status -eq 'Running') {
            Write-Status "${NameForLog}: Service started successfully (Running)." "Success"
            return $true
        } else {
            $state = if ($svc) { $svc.Status } else { "Unknown" }
            Write-Status "${NameForLog}: FAILED to start. Current state = $state" "Error"
            return $false
        }
    }

    Write-Status "${NameForLog}: Service state is '$($svc.Status)'. Not forcing start." "Warning"
    return $false
}

# ----
# explorer.exe inventory (minimal output + signature + baseline hash)
# ----
function Get-ExplorerBaseline {
    param(
        [Parameter(Mandatory)][string]$BaselinePath
    )

    if (-not (Test-Path $BaselinePath)) { return $null }

    try {
        $raw = Get-Content -Path $BaselinePath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        Write-Status "Explorer baseline file exists but could not be read/parsed: $BaselinePath - $($_.Exception.Message)" "Warning"
        return $null
    }
}

function Save-ExplorerBaseline {
    param(
        [Parameter(Mandatory)][string]$BaselinePath,
        [Parameter(Mandatory)][string]$WindowsPath,
        [Parameter(Mandatory)][string]$WindowsHash,
        [Parameter(Mandatory)][string]$SyswowPath,
        [Parameter(Mandatory)][string]$SyswowHash
    )

    try {
        $obj = [pscustomobject]@{
            CreatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Machine   = $env:COMPUTERNAME
            Explorer  = [pscustomobject]@{
                Windows = [pscustomobject]@{
                    Path   = $WindowsPath
                    SHA256 = $WindowsHash
                }
                SysWOW64 = [pscustomobject]@{
                    Path   = $SyswowPath
                    SHA256 = $SyswowHash
                }
            }
        }

        $dir = Split-Path -Parent $BaselinePath
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $obj | ConvertTo-Json -Depth 6 | Set-Content -Path $BaselinePath -Force
        Write-Status "Explorer baseline created: $BaselinePath" "Success"
    }
    catch {
        Write-Status "Failed to write explorer baseline file: $BaselinePath - $($_.Exception.Message)" "Error"
    }
}

function Get-AllExplorerExecutables {
    [CmdletBinding()]
    param(
        [string[]]$Roots = @("$env:SystemDrive\")
    )

    $found = New-Object System.Collections.Generic.List[object]
    $winSxsPath = Join-Path $env:WINDIR "WinSxS"

    foreach ($root in $Roots) {
        if (-not (Test-Path $root)) { continue }

        Get-ChildItem -Path $root -Filter "explorer.exe" -File -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object {
            $path = $_.FullName

            # Ignore WinSxS entirely
            if ($path -like "$winSxsPath*") { return }

            $sig = $null
            try { $sig = Get-AuthenticodeSignature -FilePath $path -ErrorAction Stop } catch { }

            $hash = $null
            try { $hash = (Get-FileHash -Algorithm SHA256 -Path $path -ErrorAction Stop).Hash } catch { }

            $fv = $null
            try { $fv = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path) } catch { }

            $found.Add([pscustomobject]@{
                Path           = $path
                Length         = $_.Length
                LastWriteTime  = $_.LastWriteTime
                FileVersion    = $fv.FileVersion
                ProductVersion = $fv.ProductVersion
                CompanyName    = $fv.CompanyName
                OriginalName   = $fv.OriginalFilename
                SHA256         = $hash
                SigStatus      = $sig.Status
                SigSubject     = $sig.SignerCertificate.Subject
                SigThumbprint  = $sig.SignerCertificate.Thumbprint
            }) | Out-Null
        }
    }

    return $found
}

function Log-ExplorerInventory {
    [CmdletBinding()]
    param(
        [string[]]$Roots = @("$env:SystemDrive\"),
        [int]$MaxSuspiciousToPrint = 10,
        [string]$BaselineFile = (Join-Path $LogDir "baseline_explorer.json")
    )

    $explorers = Get-AllExplorerExecutables -Roots $Roots

    if (-not $explorers -or $explorers.Count -eq 0) {
        Write-Status "No explorer.exe files found (unexpected)." "Error"
        return
    }

    Write-Status "explorer.exe scan: found $($explorers.Count) file(s) on disk (WinSxS ignored)." "Info"

    $windowsPath = Join-Path $env:WINDIR "explorer.exe"
    $syswowPath  = Join-Path (Join-Path $env:WINDIR "SysWOW64") "explorer.exe"
    $expectedPaths = @($windowsPath, $syswowPath)

    $win = $explorers | Where-Object { $_.Path -ieq $windowsPath } | Select-Object -First 1
    $wow = $explorers | Where-Object { $_.Path -ieq $syswowPath }  | Select-Object -First 1

    if ($win) {
        Write-Status "Allowed explorer.exe (Windows): $($win.Path)" "Info"
        Write-Status "  Signature: $($win.SigStatus)  Signer='$($win.SigSubject)'" "Info"
        Write-Status "  SHA256: $($win.SHA256)" "Info"
    } else {
        Write-Status "Allowed explorer.exe (Windows) NOT found at: $windowsPath" "Warning"
    }

    if ($wow) {
        Write-Status "Allowed explorer.exe (SysWOW64): $($wow.Path)" "Info"
        Write-Status "  Signature: $($wow.SigStatus)  Signer='$($wow.SigSubject)'" "Info"
        Write-Status "  SHA256: $($wow.SHA256)" "Info"
    } else {
        Write-Status "Allowed explorer.exe (SysWOW64) NOT found at: $syswowPath" "Warning"
    }

    # Baseline create/compare (stores BOTH allowed hashes)
    $baseline = Get-ExplorerBaseline -BaselinePath $BaselineFile
    if (-not $baseline) {
        if ($win -and $win.SHA256 -and $wow -and $wow.SHA256) {
            Save-ExplorerBaseline -BaselinePath $BaselineFile `
                -WindowsPath $windowsPath -WindowsHash $win.SHA256 `
                -SyswowPath $syswowPath  -SyswowHash  $wow.SHA256
            $baseline = Get-ExplorerBaseline -BaselinePath $BaselineFile
        } else {
            Write-Status "Baseline not created (missing allowed explorer.exe file(s) or hash)." "Warning"
        }
    } else {
        if ($win -and $win.SHA256 -and $baseline.Explorer.Windows.SHA256) {
            if ($win.SHA256 -ne $baseline.Explorer.Windows.SHA256) {
                Write-Status "Explorer baseline mismatch (Windows)! Current hash differs from stored baseline." "Error"
                Write-Status "  Baseline: $($baseline.Explorer.Windows.SHA256)" "Info"
                Write-Status "  Current : $($win.SHA256)" "Info"
            } else {
                Write-Status "Explorer baseline match (Windows): SHA256 matches stored baseline." "Success"
            }
        }

        if ($wow -and $wow.SHA256 -and $baseline.Explorer.SysWOW64.SHA256) {
            if ($wow.SHA256 -ne $baseline.Explorer.SysWOW64.SHA256) {
                Write-Status "Explorer baseline mismatch (SysWOW64)! Current hash differs from stored baseline." "Error"
                Write-Status "  Baseline: $($baseline.Explorer.SysWOW64.SHA256)" "Info"
                Write-Status "  Current : $($wow.SHA256)" "Info"
            } else {
                Write-Status "Explorer baseline match (SysWOW64): SHA256 matches stored baseline." "Success"
            }
        }
    }

    # Running explorer.exe processes (minimal)
    try {
        $procs = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop
        if ($procs) {
            Write-Status "Running explorer.exe process(es): $($procs.Count)" "Info"
            foreach ($p in $procs) {
                Write-Status "  PID=$($p.ProcessId) Path='$($p.ExecutablePath)'" "Info"
            }
        } else {
            Write-Status "No running explorer.exe processes detected." "Warning"
        }
    }
    catch {
        Write-Status "Unable to query running explorer.exe processes: $($_.Exception.Message)" "Warning"
    }

    # Suspicious:
    # - Any explorer.exe not in the two allowed paths
    # - OR signature is not Valid
    $suspicious = foreach ($item in $explorers) {
        $pathBad = -not ($expectedPaths -icontains $item.Path)
        $sigBad  = ($item.SigStatus -ne 'Valid')

        if ($pathBad -or $sigBad) { $item }
    }

    if (-not $suspicious -or $suspicious.Count -eq 0) {
        Write-Status "No suspicious explorer.exe variants detected." "Success"
        return
    }

    Write-Status "Suspicious explorer.exe variants: $($suspicious.Count) (showing up to $MaxSuspiciousToPrint)" "Warning"

    $shown = 0
    foreach ($e in ($suspicious | Sort-Object Path)) {
        $shown++
        if ($shown -gt $MaxSuspiciousToPrint) { break }

        $flags = @()
        if (-not ($expectedPaths -icontains $e.Path)) { $flags += "UnexpectedPath" }
        if ($e.SigStatus -ne 'Valid') { $flags += "BadSignature:$($e.SigStatus)" }

        Write-Status "  [$($flags -join ',')] $($e.Path)" "Warning"
        Write-Status "    Signature: $($e.SigStatus)  Signer='$($e.SigSubject)'" "Info"
        Write-Status "    SHA256: $($e.SHA256)" "Info"
    }

    if ($suspicious.Count -gt $MaxSuspiciousToPrint) {
        Write-Status "  (Truncated) $($suspicious.Count - $MaxSuspiciousToPrint) more suspicious explorer.exe file(s) not shown." "Info"
    }
}

# ----
# Checks + detailed logging + start attempt (if Stopped)
# ----

# HTTP (IIS)
$HasHTTP = Test-ServicePresent -Name "HTTP (IIS)" -Hint "(W3SVC)" -Test {
    $null -ne (Get-Service -Name W3SVC -ErrorAction SilentlyContinue)
}
if ($HasHTTP) {
    Log-ServiceExecutableInfo -NameForLog "HTTP (IIS)" -ServiceName "W3SVC" | Out-Null
    Ensure-ServiceRunning     -NameForLog "HTTP (IIS)" -ServiceName "W3SVC" | Out-Null
}

# FTP (IIS FTP)
$HasFTP = Test-ServicePresent -Name "FTP (IIS FTP)" -Hint "(FTPSVC)" -Test {
    $null -ne (Get-Service -Name FTPSVC -ErrorAction SilentlyContinue)
}
if ($HasFTP) {
    Log-ServiceExecutableInfo -NameForLog "FTP (IIS FTP)" -ServiceName "FTPSVC" | Out-Null
    Ensure-ServiceRunning     -NameForLog "FTP (IIS FTP)" -ServiceName "FTPSVC" | Out-Null
}

# SMTP (Windows SMTP service)
$HasSMTP = Test-ServicePresent -Name "SMTP (Windows SMTP)" -Hint "(SMTPSVC)" -Test {
    $null -ne (Get-Service -Name SMTPSVC -ErrorAction SilentlyContinue)
}
if ($HasSMTP) {
    Log-ServiceExecutableInfo -NameForLog "SMTP (Windows SMTP)" -ServiceName "SMTPSVC" | Out-Null
    Ensure-ServiceRunning     -NameForLog "SMTP (Windows SMTP)" -ServiceName "SMTPSVC" | Out-Null
}

# DNS (Windows DNS Server)
$HasDNS = Test-ServicePresent -Name "DNS Server" -Hint "(DNS)" -Test {
    $null -ne (Get-Service -Name DNS -ErrorAction SilentlyContinue)
}
if ($HasDNS) {
    Log-ServiceExecutableInfo -NameForLog "DNS Server" -ServiceName "DNS" | Out-Null
    Ensure-ServiceRunning     -NameForLog "DNS Server" -ServiceName "DNS" | Out-Null
}

# AD DS (Domain Services)
$HasAD = Test-ServicePresent -Name "Active Directory Domain Services" -Hint "(NTDS)" -Test {
    $null -ne (Get-Service -Name NTDS -ErrorAction SilentlyContinue)
}
if ($HasAD) {
    Log-ServiceExecutableInfo -NameForLog "Active Directory Domain Services" -ServiceName "NTDS" | Out-Null
    Ensure-ServiceRunning     -NameForLog "Active Directory Domain Services" -ServiceName "NTDS" | Out-Null
}

# ----
# explorer.exe inventory (allowed Windows + SysWOW64, WinSxS ignored)
# ----
Log-ExplorerInventory -Roots @("$env:SystemDrive\")

$ServicePresence = [pscustomobject]@{
    HTTP_IIS = $HasHTTP
    FTP_IIS  = $HasFTP
    SMTP     = $HasSMTP
    DNS      = $HasDNS
    AD_DS    = $HasAD
}

Write-Status ("Service presence summary: " + ($ServicePresence | ConvertTo-Json -Compress)) "Info"

# ----
# Import Windows Firewall policy from SYSVOL (.wfw)
# Expects the file to be stored directly under \\<domain>\SYSVOL\<domain>\ExportingOohlala.wfw
# ----

$FirewallPolicyName = "ExportingOohlala.wfw"

if (-not $DomainJoined) {
    Write-Status "Firewall import skipped: machine is not domain-joined (SYSVOL not available)." "Warning"
}
elseif (-not $SysVol) {
    Write-Status "Firewall import skipped: SysVol path not set." "Error"
}
else {
    $PolicyPath = Join-Path $SysVol $FirewallPolicyName

    if (-not (Test-Path $PolicyPath)) {
        Write-Status "Firewall policy file not found in SYSVOL: $PolicyPath" "Error"
    }
    else {
        Write-Status "Importing Windows Firewall policy from: $PolicyPath" "Info"
        try {
            & netsh advfirewall import "$PolicyPath" | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Status "Firewall policy imported successfully from SYSVOL." "Success"
            } else {
                Write-Status "Firewall policy import failed. netsh exit code: $LASTEXITCODE" "Error"
            }
        }
        catch {
            Write-Status "Firewall policy import threw an exception: $($_.Exception.Message)" "Error"
        }
    }
}

# ----
# Ensure Windows Firewall has ALLOW rules for scored services that are PRESENT
# HTTP/HTTPS should be allowed BOTH directions (Inbound + Outbound)
# DNS + AD intentionally omitted
# Uses: $HasHTTP, $HasFTP, $HasSMTP
# ----

function Ensure-AllowRule {
    param(
        [Parameter(Mandatory)][string]$RuleName,
        [Parameter(Mandatory)][string]$DisplayGroup,
        [Parameter(Mandatory)][ValidateSet("TCP","UDP")][string]$Protocol,
        [Parameter(Mandatory)][string]$Port,  # local port for inbound, remote port for outbound (see below)
        [Parameter(Mandatory)][ValidateSet("Inbound","Outbound")][string]$Direction,
        [Parameter(Mandatory)][string]$Description,
        [string[]]$Profile = @("Domain","Private","Public")
    )

    try {
        $existing = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue

        if (-not $existing) {
            $rule = New-NetFirewallRule `
                -DisplayName $RuleName `
                -Group $DisplayGroup `
                -Enabled True `
                -Direction $Direction `
                -Action Allow `
                -Protocol $Protocol `
                -Profile $Profile `
                -Description $Description
            if ($Direction -eq "Inbound") {
                $rule | Set-NetFirewallPortFilter -Protocol $Protocol -LocalPort $Port | Out-Null
            } else {
                $rule | Set-NetFirewallPortFilter -Protocol $Protocol -RemotePort $Port | Out-Null
            }

            Write-Status "Firewall allow rule created: $RuleName ($Direction $Protocol/$Port)" "Success"
        }
        else {
            $existing | Set-NetFirewallRule -Enabled True -Action Allow -Direction $Direction | Out-Null

            if ($Direction -eq "Inbound") {
                $existing | Set-NetFirewallPortFilter -Protocol $Protocol -LocalPort $Port | Out-Null
            } else {
                $existing | Set-NetFirewallPortFilter -Protocol $Protocol -RemotePort $Port | Out-Null
            }

            Write-Status "Firewall allow rule already exists (ensured): $RuleName" "Info"
        }
    }
    catch {
        Write-Status "Failed to ensure firewall rule '$RuleName': $($_.Exception.Message)" "Error"
    }
}

# ----
# HTTP/HTTPS: allow BOTH inbound (web server) and outbound (client browsing)
# ----
if ($HasHTTP) {
    Ensure-AllowRule -RuleName "CCDC - Allow HTTP (TCP 80) In"  -DisplayGroup "CCDC Scored Services" `
        -Direction Inbound -Protocol TCP -Port 80 `
        -Description "Allow inbound HTTP to IIS (W3SVC) for scoring."

    # Outbound from this machine (web browsing/downloads to remote ports 80/443)
    Ensure-AllowRule -RuleName "CCDC - Allow HTTP (TCP 80) Out"  -DisplayGroup "CCDC Internet Access" `
        -Direction Outbound -Protocol TCP -Port 80 `
        -Description "Allow outbound HTTP to remote port 80 (web browsing/downloads)."

    Ensure-AllowRule -RuleName "CCDC - Allow HTTPS (TCP 443) Out" -DisplayGroup "CCDC Internet Access" `
        -Direction Outbound -Protocol TCP -Port 443 `
        -Description "Allow outbound HTTPS to remote port 443 (web browsing/downloads)."
}

# ----
# FTP (server inbound)
# ----
if ($HasFTP) {
    Ensure-AllowRule -RuleName "CCDC - Allow FTP Control (TCP 21) In" -DisplayGroup "CCDC Scored Services" `
        -Direction Inbound -Protocol TCP -Port 21 `
        -Description "Allow inbound FTP control channel (FTPSVC) for scoring."

    Ensure-AllowRule -RuleName "CCDC - Allow FTP Data Active (TCP 20) In" -DisplayGroup "CCDC Scored Services" `
        -Direction Inbound -Protocol TCP -Port 20 `
        -Description "Allow inbound FTP active mode data channel (if used)."
}

# ----
# SMTP (server inbound)
# ----
if ($HasSMTP) {
    Ensure-AllowRule -RuleName "CCDC - Allow SMTP (TCP 25) In" -DisplayGroup "CCDC Scored Services" `
        -Direction Inbound -Protocol TCP -Port 25 `
        -Description "Allow inbound SMTP to SMTPSVC for scoring."
}

Stop-Transcript
