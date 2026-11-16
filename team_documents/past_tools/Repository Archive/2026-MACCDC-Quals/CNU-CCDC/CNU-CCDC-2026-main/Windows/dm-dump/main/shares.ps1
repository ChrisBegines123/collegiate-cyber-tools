# Administrator
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit }

#Delete shares
net share

do {
$Share = Read-host -Prompt "Should a share be removed? Y/N"
    if ($Share -eq "Y") {
        $DelShare = Read-Host -Prompt "Share?"
            net share $DelShare /delete | out-null }
    else {break}
    net share
    } while ($Share -eq "Y") 