$WazuhManager = "10.0.0.2"
$AgentName = $env:COMPUTERNAME

$MsiUrl  = "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.2-1.msi"
$MsiPath = "$env:TEMP\wazuh-agent-4.14.2-1.msi"

Write-Host "Downloading Wazuh agent..."
Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiPath

Write-Host "Installing Wazuh agent..."
Start-Process msiexec.exe -Wait -ArgumentList `
"/i `"$MsiPath`" /q WAZUH_MANAGER=`"$WazuhManager`" WAZUH_AGENT_NAME=`"$AgentName`""

Write-Host "Starting service..."
Set-Service WazuhSvc -StartupType Automatic
Start-Service WazuhSvc

Write-Host "Wazuh agent installed and connected to $WazuhManager"

# if powershell blocks script try: Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
