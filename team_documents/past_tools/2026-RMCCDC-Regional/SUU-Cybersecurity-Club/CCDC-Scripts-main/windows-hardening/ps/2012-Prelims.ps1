param($ROOT = "C:\Users\$Env:UserName\Desktop")

$LOGS = "$ROOT\PS-LOGS"

echo "`nCreating log file..."
New-Item -Path $LOGS\PS-PRELIMS-OUT.txt -Force -ItemType "file"

. {
    echo `n"
**************************************
Start Time: $(get-date)
UserName: $env:username
UserDomain: $env:USERDNSDOMAIN
ComputerName: $env:COMPUTERNAME
Windows version: $((Get-WmiObject win32_operatingsystem).version)
**************************************
"
    echo "`nSetting Registry to use strong encryption..."
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NetFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -Value '1' -Type DWord
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NetFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -Value '1' -Type DWord

} | Tee-Object $LOGS\PS-PRELIMS-OUT.txt