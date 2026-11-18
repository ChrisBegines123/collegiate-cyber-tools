# ==========================================
# Enable Full Audit Logging + Firewall Logs
# Log location: C:\Windows\LogFiles\
# ==========================================

# Ensure log directory exists
$logDir = "C:\Windows\LogFiles"
if (!(Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

Write-Host "Enabling Windows Audit Policies..." -ForegroundColor Cyan

$categories = @(
  "Account Logon",
  "Account Management",
  "DS Access",
  "Logon/Logoff",
  "Object Access",
  "Policy Change",
  "Privilege Use",
  "Detailed Tracking",
  "System"
)

foreach ($cat in $categories) {
    auditpol /set /category:"$cat" /success:enable /failure:enable | Out-Null
}

Write-Host "Audit policies enabled." -ForegroundColor Green


# ==========================================
# Enable Firewall Logging for ALL profiles
# ==========================================

Write-Host "Enabling Firewall Logging to C:\Windows\LogFiles..." -ForegroundColor Cyan

$profiles = @("Domain", "Private", "Public")

foreach ($profile in $profiles) {

    $logPath = "C:\Windows\LogFiles\pfirewall_$profile.log"

    Set-NetFirewallProfile `
        -Profile $profile `
        -LogAllowed True `
        -LogBlocked True `
        -LogFileName $logPath `
        -LogMaxSizeKilobytes 65536

    Write-Host "Firewall logging enabled for $profile profile -> $logPath"
}


# ==========================================
# Enable command-line process logging
# ==========================================

reg add HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System\Audit `
 /v ProcessCreationIncludeCmdLine_Enabled `
 /t REG_DWORD `
 /d 1 `
 /f | Out-Null

Write-Host "Process command-line logging enabled." -ForegroundColor Green


# ==========================================
# Verify settings
# ==========================================

Write-Host "`nAudit policy status:" -ForegroundColor Yellow
auditpol /get /category:*

Write-Host "`nFirewall logging status:" -ForegroundColor Yellow
Get-NetFirewallProfile | Select Name, LogAllowed, LogBlocked, LogFileName
