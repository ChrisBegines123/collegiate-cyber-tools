## Get-ServiceInfo.ps1
## Script to find out all services on your machine and what account is used to start it as well as its current state

## Define labels for output
$serviceName = @{Name='ServiceName'; Expression = {$_.Name}}
$serviceDisplayName = @{Name = 'Service DisplayName'; Expression ={$_.Caption}}

## SystemName -name of computer/server
## Name -Service Name
## Caption - Service Display Name
## StartMode -Auto, Auto-delay, Manual, Disabled
## StartName -Account used to start the service
## State - Running or Stopped

## Command
Get-CimInstance -ClassName Win32_Service -Filter "StartName != 'LocalSystem' AND NOT StartName LIKE 'NT Authority%'" | Select-Object SystemName, $serviceName, $serviceDisplayName, StartMode, StartName, State | Sort-Object StartName
pause
