# ==============================================================================
# Script Name : check-remote.ps1
# Description : Quick remote login checker for threat hunting triage
# Author      : Tyler Olson
# Organization: Missouri State University
# Version     : 1.0
# ==============================================================================

$Since = (Get-Date).AddHours(-24)

function Write-Header { param([string]$T)
    Write-Host "`n--- $T ---" -ForegroundColor Cyan
}

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host "[ERROR] Run as Administrator" -ForegroundColor Red; exit 1 }

Write-Host "`nRemote Login Hunter | Last 24hrs | $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Magenta

# --- Successful Remote Logons (4624 Type 3/10) --------------------------------
Write-Header "Successful Remote Logons"
try {
    Get-WinEvent -FilterHashtable @{ LogName='Security'; Id=4624; StartTime=$Since } -EA Stop |
    ForEach-Object {
        $d = ([xml]$_.ToXml()).Event.EventData.Data
        $type = ($d | Where-Object Name -eq 'LogonType').'#text'
        if ($type -notin '3','10') { return }
        $user = ($d | Where-Object Name -eq 'TargetUserName').'#text'
        $ip   = ($d | Where-Object Name -eq 'IpAddress').'#text'
        if ($user -match '\$$' -or $ip -in '-','127.0.0.1','::1') { return }
        Write-Host "  $($_.TimeCreated.ToString('HH:mm:ss'))  $user  from $ip  [Type $type]" -ForegroundColor Green
    }
} catch { Write-Host "  (no events or access denied)" -ForegroundColor DarkGray }

# --- Failed Logons (4625) -----------------------------------------------------
Write-Header "Failed Remote Logon Attempts"
$failCounts = @{}
try {
    Get-WinEvent -FilterHashtable @{ LogName='Security'; Id=4625; StartTime=$Since } -EA Stop |
    ForEach-Object {
        $d    = ([xml]$_.ToXml()).Event.EventData.Data
        $type = ($d | Where-Object Name -eq 'LogonType').'#text'
        if ($type -notin '3','10') { return }
        $user = ($d | Where-Object Name -eq 'TargetUserName').'#text'
        $ip   = ($d | Where-Object Name -eq 'IpAddress').'#text'
        if ($ip -in '-','127.0.0.1','::1') { return }
        $failCounts[$ip] = ($failCounts[$ip] ?? 0) + 1
        Write-Host "  $($_.TimeCreated.ToString('HH:mm:ss'))  $user  from $ip" -ForegroundColor Yellow
    }
    $failCounts.GetEnumerator() | Where-Object Value -ge 5 |
        ForEach-Object { Write-Host "  [!] BRUTE FORCE? $($_.Key) - $($_.Value) failures" -ForegroundColor Red }
} catch { Write-Host "  (no events or access denied)" -ForegroundColor DarkGray }

# --- RDP Sessions (TerminalServices log) --------------------------------------
Write-Header "RDP Sessions"
try {
    Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'; Id=21,24,25; StartTime=$Since } -EA Stop |
    ForEach-Object {
        $d  = ([xml]$_.ToXml()).Event.UserData.EventXML
        Write-Host "  $($_.TimeCreated.ToString('HH:mm:ss'))  EventID $($_.Id)  $($d.User)  from $($d.Address)" -ForegroundColor White
    }
} catch { Write-Host "  (no events or access denied)" -ForegroundColor DarkGray }

# --- Live Remote Connections --------------------------------------------------
Write-Header "Live Remote Connections"
$ports = @{ 3389='RDP'; 5985='WinRM'; 5986='WinRM-S'; 22='SSH'; 445='SMB' }
Get-NetTCPConnection -State Established -EA SilentlyContinue |
    Where-Object { $_.LocalPort -in $ports.Keys -and $_.RemoteAddress -notin '127.0.0.1','::1' } |
    ForEach-Object {
        $proc = try { (Get-Process -Id $_.OwningProcess -EA Stop).Name } catch { "PID $($_.OwningProcess)" }
        Write-Host "  $($ports[$_.LocalPort])  $($_.RemoteAddress):$($_.RemotePort)  ($proc)" -ForegroundColor Cyan
    }

Write-Host "`n[DONE]`n" -ForegroundColor Magenta