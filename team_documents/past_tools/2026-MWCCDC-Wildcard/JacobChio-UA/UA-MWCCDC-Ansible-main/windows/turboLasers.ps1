[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Install-Module -Name PSWindowsUpdate -Force
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force -Scope Process
Import-Module PSWindowsUpdate
Add-WUServiceManager -MicrosoftUpdate -Confirm:$false -Silent
Get-WindowsUpdate -AcceptAll -Install -Category 'Security Updates' -IgnoreReboot