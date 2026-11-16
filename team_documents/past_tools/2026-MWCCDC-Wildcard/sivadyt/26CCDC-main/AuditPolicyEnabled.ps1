# Enable Basic Audit Policy categories (Success + Failure)
# Run PowerShell as Administrator

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

Write-Host "Enabling auditing (Success+Failure) for categories:" -ForegroundColor Cyan
$categories | ForEach-Object { Write-Host " - $_" }

foreach ($cat in $categories) {
  & auditpol.exe /set /category:"$cat" /success:enable /failure:enable | Out-Null
}

Write-Host "`nDone. Current settings:" -ForegroundColor Green
& auditpol.exe /get /category:* 
