param($ROOT = "C:\Users\$Env:UserName\Desktop")

$DOCS = "C:\Users\$Env:UserName\Documents"
$LOGS = "$ROOT\PS-LOGS"

$WAZUH_URL = "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.8.0-1.msi"
$KF_URL = "https://www.kfsensor.net/kfsensor/download/kfsens40.msi"
$AUTORUNS_URL = "https://download.sysinternals.com/files/Autoruns.zip"
$REG_MAN_URL = "https://www.resplendence.com/download/RegistrarHomeV9.exe"
$CHROME_URL = "https://download.mozilla.org/?product=firefox-stub&os=win64&lang=en-US"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

echo "`nCreating log file..."
New-Item -Path $LOGS\PS-SOFTWARE-OUT.txt -Force -ItemType "file"
Set-Alias -Name wget -Value Invoke-WebRequest

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

    echo "`n******************** DOWNLOADING AND INSTALLING WAZUH AGENT ********************`n"

    wget $WAZUH_URL -OutFile "$ROOT\wazuh-agent.msi"
    $IP = Read-Host "Enter the wazuh manager IP"
    & $ROOT\wazuh-agent.msi /q WAZUH_MANAGER=$IP
    Start-Sleep -Seconds 4
    NET START Wazuh

    echo "`n******************** DOWNLOADING AUTORUNS ********************`n"

    wget $AUTORUNS_URL -OutFile $DOCS\autoruns.zip
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory("$DOCS\autoruns.zip", "$ROOT\autoruns")

    echo "`n******************** DOWNLOADING REGISTRY MANAGER ********************`n"

    wget $REG_MAN_URL -OutFile "$ROOT\regman-installer.exe"

} | Tee-Object $LOGS\PS-SOFTWARE-OUT.txt