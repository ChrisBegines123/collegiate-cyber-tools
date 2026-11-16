#Requires -RunAsAdministrator
# CCDC26 - Golden/Silver Ticket Detection via Kerberos Ticket Lifetime Analysis
# Enumerates Kerberos sessions and flags tickets with abnormal lifetimes.

$ErrorActionPreference = "Continue"

function Info    { param([string]$M) Write-Host "[INFO] $M" -ForegroundColor Blue }
function OK      { param([string]$M) Write-Host "[OK]   $M" -ForegroundColor Green }
function Warn    { param([string]$M) Write-Host "[WARN] $M" -ForegroundColor Yellow }
function Finding { param([string]$M) Write-Host "[FINDING] $M" -ForegroundColor Red }

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Kerberos Ticket Lifetime Analysis" -ForegroundColor Cyan
Write-Host "  Computer: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Default Kerberos policy values
$defaultTGTLifetimeHours = 10
$defaultRenewalDays = 7
$maxAcceptableTGTHours = 12
$maxAcceptableRenewalDays = 8

$findings = 0

# Parse klist output for all logon sessions
Info "Enumerating Kerberos tickets via klist..."

$klistOutput = klist sessions 2>&1
if ($LASTEXITCODE -ne 0) {
    Warn "klist sessions failed; trying klist directly"
    $klistOutput = klist 2>&1
}

# Parse individual sessions
$sessionIds = @()
if ($klistOutput -match 'LogonId is') {
    $klistOutput | ForEach-Object {
        if ($_ -match '\[(\d+)\]\s+Session\s+(\d+)\s+(\S+)\s+(\S+)\s+(.+)') {
            $sessionIds += @{ Id = $Matches[2]; Luid = $Matches[1]; User = $Matches[5].Trim() }
        }
    }
}

Info "Found $($sessionIds.Count) logon sessions"

foreach ($session in $sessionIds) {
    $tickets = klist -li "$($session.Id)" 2>&1
    if (-not $tickets) { continue }

    $currentTicket = $null
    foreach ($line in $tickets) {
        if ($line -match '#\d+>\s+Client:\s+(.+)') {
            $currentTicket = @{ Client = $Matches[1].Trim(); Server = ""; Start = $null; End = $null; Renew = $null }
        }
        if ($currentTicket -and $line -match 'Server:\s+(.+)') { $currentTicket.Server = $Matches[1].Trim() }
        if ($currentTicket -and $line -match 'KerbTicket\s+Encryption.*:\s+(.+)') { $currentTicket.Encryption = $Matches[1].Trim() }
        if ($currentTicket -and $line -match 'Start Time:\s+(.+)') {
            try { $currentTicket.Start = [datetime]::Parse($Matches[1].Trim()) } catch {}
        }
        if ($currentTicket -and $line -match 'End Time:\s+(.+)') {
            try { $currentTicket.End = [datetime]::Parse($Matches[1].Trim()) } catch {}
        }
        if ($currentTicket -and $line -match 'Renew Time:\s+(.+)') {
            try { $currentTicket.Renew = [datetime]::Parse($Matches[1].Trim()) } catch {}

            # Process completed ticket
            if ($currentTicket.Start -and $currentTicket.End) {
                $lifetime = ($currentTicket.End - $currentTicket.Start)
                $lifetimeHours = [math]::Round($lifetime.TotalHours, 1)

                $flags = @()
                if ($lifetimeHours -gt $maxAcceptableTGTHours) {
                    $flags += "Lifetime ${lifetimeHours}h exceeds max ${maxAcceptableTGTHours}h"
                }

                if ($currentTicket.Renew) {
                    $renewSpan = ($currentTicket.Renew - $currentTicket.Start)
                    $renewDays = [math]::Round($renewSpan.TotalDays, 1)
                    if ($renewDays -gt $maxAcceptableRenewalDays) {
                        $flags += "Renewal ${renewDays}d exceeds max ${maxAcceptableRenewalDays}d"
                    }
                }

                if ($currentTicket.Server -match 'krbtgt' -and $currentTicket.Encryption -and $currentTicket.Encryption -match 'RC4') {
                    $flags += "TGT using RC4 encryption (golden ticket indicator)"
                }

                if ($flags.Count -gt 0) {
                    $findings++
                    Finding "Suspicious ticket for $($session.User)"
                    Write-Host "    Server:   $($currentTicket.Server)" -ForegroundColor Gray
                    Write-Host "    Lifetime: ${lifetimeHours}h (default: ${defaultTGTLifetimeHours}h)" -ForegroundColor Gray
                    Write-Host "    Encrypt:  $($currentTicket.Encryption)" -ForegroundColor Gray
                    Write-Host "    Flags:    $($flags -join '; ')" -ForegroundColor Yellow
                }
            }
            $currentTicket = $null
        }
    }
}

# Also check for TGTs via event logs (Event ID 4768 with unusual properties)
Info "Checking Event ID 4768 (TGT requests) for anomalies..."
try {
    $tgtEvents = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4768} -MaxEvents 100 -ErrorAction Stop
    foreach ($e in $tgtEvents) {
        $xml = [xml]$e.ToXml()
        $data = @{}
        foreach ($d in $xml.Event.EventData.Data) { if ($d.Name) { $data[$d.Name] = $d.'#text' } }

        # RC4 (0x17) for TGT is suspicious on modern domains
        if ($data['TicketEncryptionType'] -eq '0x17') {
            $findings++
            Finding "RC4 TGT request (possible golden ticket or downgrade)"
            Write-Host "    User:    $($data['TargetUserName'])" -ForegroundColor Gray
            Write-Host "    IP:      $($data['IpAddress'])" -ForegroundColor Gray
            Write-Host "    Time:    $($e.TimeCreated)" -ForegroundColor Gray
        }
    }
} catch {
    Info "No 4768 events available (auditing may not be enabled)"
}

Write-Host ""
if ($findings -gt 0) {
    Finding "$findings suspicious Kerberos ticket(s) detected"
    Write-Host "  Investigate with: klist purge (to clear tickets)" -ForegroundColor Yellow
    Write-Host "  If golden ticket confirmed: rotate krbtgt password TWICE" -ForegroundColor Yellow
} else {
    OK "No suspicious Kerberos tickets detected"
}
