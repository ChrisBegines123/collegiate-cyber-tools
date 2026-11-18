$action = New-ScheduledTaskAction -Execute "C:\Program Files\ClamAV\clamscan.exe" -Argument "C:\"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date.AddHours((Get-Date).Hour + 1) -RepetitionInterval (New-TimeSpan -Minutes 60)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask `
-TaskName "ClamAV Hourly Scan" `
-Action $action `
-Trigger $trigger `
-Principal $principal `
-Description "Runs an hourly scan of ClamAV on the C: drive."
