# ----
# Logging Setup
# ----
$LogDir = "C:\Logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
$TimestampName = Get-Date -Format "HHmm"
$LogFile = Join-Path $LogDir "Audit_$TimestampName.log"
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
    "Error"   { Write-Host "[ERROR] $Message" -ForegroundColor Red }
    default   { Write-Host "[INFO] $Message" }
 }
}

Write-Status "Audit started"

# ----
# Active Directory Detection
# ----
$ADAvailable = $false

$ADCmd = Get-Command Get-ADUser -ErrorAction SilentlyContinue
if ($ADCmd -and $ADCmd.Source -eq "ActiveDirectory"){
    $ADAvailable = $true
    Write-Status "Active Directory PowerShell module detected" "Success"
} else {
    Write-Status "Active Directory PowerShell module not available" "Info"
}

# ----
# User & Group Audit
# ----
Write-Status "Auditing local users"
Get-LocalUser | Select Name, Enabled, PrincipalSource | Format-Table

Write-Status "Auditing local group memberships"
Get-LocalGroup | ForEach-Object {
    Write-Host "`nGroup: $($_.Name)" -ForegroundColor Cyan
    try {
        Get-LocalGroupMember $_.Name | Select Name, ObjectClass | Format-Table
    } catch {
        Write-Status "Failed to enumerate group $($_.Name)" "Warning"
    }
}

if ($ADAvailable) {
    Write-Status "Auditing Active Directory users"
    Get-ADUser -Filter * -Properties Enabled | Select SamAccountName, Enabled | Format-Table

    Write-Status "Auditing privileged AD group memberships"
    foreach ($user in Get-ADUser -Filter *) {
        Write-Host "`n$user"
        Get-ADPrincipalGroupMembership $user | Select Name | Format-Table
    }

    Write-Status "Auditing foreign security principals"
    Get-ADObject -Filter { ObjectClass -eq "foreignSecurityPrincipal" }
}

# ----
# Scheduled Tasks Audit
# ----
Write-Status "Starting scheduled tasks audit"
$WhitelistFile = "C:\Logs\ScheduledTasksAllowed.txt"

if (-not (Test-Path $WhitelistFile)) {
    Write-Status "Whitelist file not found. Creating new whitelist from current scheduled tasks." "Warning"
    $CurrentTasks = Get-ScheduledTask | ForEach-Object { "$($_.TaskName) $($_.TaskPath.TrimEnd('\'))" }
    $CurrentTasks | Sort-Object -Unique | Out-File -FilePath $WhitelistFile -Encoding UTF8
    Write-Status "Whitelist file generated at $WhitelistFile" "Success"
} else {
    Write-Status "Auditing scheduled tasks against whitelist"
    $AllowedTasks = Get-Content $WhitelistFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("#") }
    $CurrentTasks = Get-ScheduledTask | ForEach-Object { "$($_.TaskName) $($_.TaskPath.TrimEnd('\'))" }
    $UnexpectedTasks = $CurrentTasks | Where-Object { $AllowedTasks -notcontains $_ }
    if ($UnexpectedTasks.Count -gt 0) {
        Write-Status "Unexpected scheduled tasks detected!" "Warning"
        $UnexpectedTasks | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    } else {
        Write-Status "No unexpected scheduled tasks detected" "Success"
    }
}

# ----
# Active Sessions
# ----
Write-Status "Auditing active user sessions"
query user

# ----
# Network Audit
# ----
Write-Status "Auditing network connections"
Get-NetTCPConnection |
Select LocalAddress, LocalPort, RemoteAddress, RemotePort, State,
@{Name="ProcessName";Expression={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name}} |
Format-Table

# ----
# ARP Table Baseline & Comparison
# ----
Write-Status "Auditing ARP table"
$ArpBaselineFile = Join-Path $LogDir "arp_baseline.txt"
$CurrentArp = arp -a

if (-not (Test-Path $ArpBaselineFile)) {
    Write-Status "ARP baseline not found. Creating baseline." "Warning"
    $CurrentArp | Out-File $ArpBaselineFile -Encoding UTF8
} else {
    Write-Status "ARP baseline found. Comparing current ARP table."
    $BaselineArp = Get-Content $ArpBaselineFile
    $Differences = Compare-Object -ReferenceObject $BaselineArp -DifferenceObject $CurrentArp -PassThru
    if ($Differences) {
        Write-Status "ARP table changes detected!" "Warning"
        $Differences | Format-Table
    } else {
        Write-Status "No ARP table changes detected" "Success"
    }
}

# ----
# MAC Address Baseline & Comparison
# ----
Write-Status "Auditing physical MAC addresses"
$MacBaselineFile = Join-Path $LogDir "mac_baseline.txt"
$CurrentMac = Get-NetAdapter -Physical | Where-Object { $_.MacAddress } |
    Select-Object -ExpandProperty MacAddress | ForEach-Object { $_.ToUpper().Trim() } | Sort-Object -Unique

if (-not (Test-Path $MacBaselineFile)) {
    Write-Status "MAC baseline not found. Creating baseline." "Warning"
    $CurrentMac | Out-File $MacBaselineFile
} else {
    Write-Status "MAC baseline found. Comparing current MAC addresses."
    $BaselineMac = Get-Content $MacBaselineFile | ForEach-Object { $_.ToUpper().Trim() } | Sort-Object -Unique
    $Differences = Compare-Object -ReferenceObject $BaselineMac -DifferenceObject $CurrentMac -PassThru
    if ($Differences.Count -gt 0) {
        Write-Status "MAC address changes detected!" "Warning"
        $Differences | Format-Table
    } else {
        Write-Status "No MAC address changes detected" "Success"
    }
}

# ----
# Services Audit
# ----
Write-Status "Auditing non-default services"
Get-WmiObject Win32_Service |
Where-Object { $_.PathName -notmatch "Windows|Microsoft" } |
Select Name, State, PathName | Format-Table

# ----
# Password Policy
# ----
Write-Status "Auditing password policy"
if ($ADAvailable) {
    Get-ADDefaultDomainPasswordPolicy
} else {
    secedit /export /cfg "$LogDir\secpol.inf" | Out-Null
    Select-String "$LogDir\secpol.inf" -Pattern "Password"
}

# ----
# DNS & Hosts File
# ----
Write-Status "Auditing DNS cache"
Get-DnsClientCache | Format-Table
Write-Status "Auditing hosts file"
Get-Content "C:\Windows\System32\drivers\etc\hosts"

# ----
# Home Directory Audit
# ----
Write-Status "Auditing user home directories and permissions"
$HomeDirs = Get-ChildItem "C:\Users" -Directory | Where-Object { $_.Name -notin @("Public","Default","Default User","All Users") }
foreach ($dir in $HomeDirs) {
    Write-Host "`nInspecting $($dir.FullName)" -ForegroundColor Cyan
    Write-Status "Listing files"
    Get-ChildItem $dir.FullName -Recurse -ErrorAction SilentlyContinue | Select FullName, Length | Format-Table
    Write-Status "Checking permissions"
    Get-Acl $dir.FullName | Format-List
}

# ----
# SMB Shares Audit
# ----
Write-Status "Auditing SMB shares"
Get-SmbShare | Select Name, Path, Description | Format-Table

# ----
# Audit Complete
# ----
Write-Status "Audit completed successfully" "Success"
Write-Status "Log file saved to $LogFile"

Stop-Transcript
