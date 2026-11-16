<# 
    ftp-guardian-lite.ps1
    - Checks FTP service health
    - Checks firewall status
    - Ensures ports 20/21 allowed, 23/445/139/3389 blocked
    - A version which tests the Loops every 59 seconds and logs to C:\ftp-guardian\lite.log
#>

$ErrorActionPreference = "SilentlyContinue"

$LogDir  = "C:\ftp-guardian"
$LogFile = Join-Path $LogDir "lite.log"

$PortsToBlock     = @(23,445,139,3389)   # high-risk ports [file:54][file:55]
$FtpPortsToAllow  = @(20,21)             # FTP ports [file:54]
$LoopIntervalSeconds = 59

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    if (!(Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    $line | Tee-Object -FilePath $LogFile -Append
}

Write-Log "===== FTP Guardian LITE Started ====="

function Check-FirewallBase {
    $profiles = Get-NetFirewallProfile
    foreach ($p in $profiles) {
        Write-Log ("Profile {0}: Enabled={1}, Inbound={2}, Outbound={3}" -f $p.Name,$p.Enabled,$p.DefaultInboundAction,$p.DefaultOutboundAction)
    }
}

function Check-FTPService {
    try {
        $svc = Get-Service -Name "ftpsvc" -ErrorAction Stop
        Write-Log ("ftpsvc status: {0}, StartType: {1}" -f $svc.Status, $svc.StartType)
        if ($svc.Status -ne "Running") {
            Write-Log "ftpsvc not running, attempting start..." "WARN"
            Start-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Log "Microsoft FTP Service (ftpsvc) not found." "WARN"
    }
}

function Check-BlockedPorts {
    foreach ($port in $PortsToBlock) {
        $fwRules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object {
            ($_.Direction -eq "Inbound") -and ($_.Enabled -eq "True") -and ($_.Action -eq "Allow")
        }

        $inboundOpen = $false
        foreach ($r in $fwRules) {
            $pf = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $r -ErrorAction SilentlyContinue
            if ($pf -and $pf.LocalPort -eq "$port") {
                $inboundOpen = $true
                break
            }
        }

        if ($inboundOpen) {
            Write-Log "Port $port appears ALLOWED inbound. Verify this is required." "WARN"
        } else {
            Write-Log "Port $port not explicitly allowed inbound (good)." "INFO"
        }
    }
}

function Check-FTPPortsAllowed {
    foreach ($port in $FtpPortsToAllow) {
        $fwRules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object {
            ($_.Direction -eq "Inbound") -and ($_.Enabled -eq "True") -and ($_.Action -eq "Allow")
        }

        $foundAllow = $false
        foreach ($r in $fwRules) {
            $pf = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $r -ErrorAction SilentlyContinue
            if ($pf -and $pf.LocalPort -eq "$port") {
                $foundAllow = $true
                break
            }
        }

        if ($foundAllow) {
            Write-Log "FTP port $port allowed inbound." "INFO"
        } else {
            Write-Log "FTP port $port NOT explicitly allowed inbound. Check firewall rules." "WARN"
        }
    }
}

Check-FirewallBase
Check-FTPService
Check-BlockedPorts
Check-FTPPortsAllowed

Write-Log "Initial checks done. Entering monitoring loop ($LoopIntervalSeconds seconds)."

while ($true) {
    Write-Log "----- Loop start -----"
    Check-FTPService
    Check-BlockedPorts
    Check-FTPPortsAllowed
    Write-Log "----- Loop end -----"
    Start-Sleep -Seconds $LoopIntervalSeconds
}
