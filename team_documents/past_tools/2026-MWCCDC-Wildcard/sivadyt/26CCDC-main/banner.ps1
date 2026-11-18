# Set-LogonBanner.ps1
# Run as Administrator

$Title = "AUTHORIZED USE ONLY"

$Text = @"
This system is the property of the organization and may be accessed only by authorized users.
By continuing to use this system, you acknowledge and consent to monitoring, recording, and
review of all activity for security and administrative purposes.

There is no expectation of privacy. Unauthorized access or misuse is strictly prohibited and
may result in disciplinary action, civil penalties, and criminal prosecution.

If you are not an authorized user, disconnect immediately.
"@

$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

New-Item -Path $RegPath -Force | Out-Null
Set-ItemProperty -Path $RegPath -Name "legalnoticecaption" -Type String -Value $Title
Set-ItemProperty -Path $RegPath -Name "legalnoticetext"    -Type String -Value $Text

Write-Host "Logon banner set. (Applies at next sign-in.)"
