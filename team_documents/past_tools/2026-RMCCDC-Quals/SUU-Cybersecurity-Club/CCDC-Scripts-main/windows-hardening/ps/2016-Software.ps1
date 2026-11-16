param($ROOT = "C:\Users\$Env:UserName\Desktop")

$ProgressPreference = 'SilentlyContinue'
$DOCS = "C:\Users\$Env:UserName\Documents"
$LOGS = "$ROOT\PS-LOGS"

Start-Transcript -Path "$LOGS\PS-SOFTWARE-OUT.txt"

. {
    $WAZUH_URL = "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.8.0-1.msi"
    $KF_URL = "https://www.kfsensor.net/kfsensor/download/kfsens40.msi"
    $REG_MAN_URL = "https://www.resplendence.com/download/RegistrarHomeV9.exe"
    $SYSINTERNALS_URL = "https://download.sysinternals.com/files/SysinternalsSuite.zip"
    $2016_BASELINE_URL = "https://download.microsoft.com/download/8/5/C/85C25433-A1B0-4FFA-9429-7E023E7DA8D8/Windows%2010%20Version%201607%20and%20Windows%20Server%202016%20Security%20Baseline.zip"
    $LGPO_URL = "https://download.microsoft.com/download/8/5/C/85C25433-A1B0-4FFA-9429-7E023E7DA8D8/LGPO.zip"
    $POLICYANALYZER_URL = "https://download.microsoft.com/download/8/5/C/85C25433-A1B0-4FFA-9429-7E023E7DA8D8/PolicyAnalyzer.zip"
	$WORMHOLE_URL = "https://github.com/aquacash5/magic-wormhole-exe/releases/download/0.17.0/wormhole.exe"
	$SHARPHOUND_URL = "https://github.com/SpecterOps/SharpHound/releases/download/v2.5.13/SharpHound-v2.5.13.zip"
	$SURICATA_URL = "https://www.openinfosecfoundation.org/download/windows/Suricata-7.0.8-1-64bit.msi"
	$RULES_URL = "https://rules.emergingthreats.net/open/suricata-7.0.3/emerging-all.rules.zip"
	$NPCAP_URL = "https://npcap.com/dist/npcap-1.80.exe"

    echo "`n******************** DOWNLOADING AND INSTALLING WAZUH AGENT ********************`n"

    wget $WAZUH_URL -OutFile "$ROOT\wazuh-agent.msi"
    $IP = Read-Host "Enter the wazuh manager IP"
    & $ROOT\wazuh-agent.msi /q WAZUH_MANAGER=$IP

	$service = (Get-Service Wazuh)
	while ($service -eq $null) {
		Start-Sleep -Seconds 1
		echo "Waiting for Wazuh to install..."
		$service = (Get-Service Wazuh)
	}
    NET START Wazuh

    echo "`n******************** DOWNLOADING AND INSTALLING SURICATA ********************`n"

	#Get IP Address for Suricata
	$IP=(Get-NetIPAddress | Where-Object {$_.AddressState -eq "Preferred" -and $_.ValidLifetime -lt "24:00:00"}).IPAddress
	echo $IP

	#Download and install npcap
	wget $NPCAP_URL -Outfile $DOCS\npcap.exe
	& $DOCS\npcap.exe
	Read-Host "npcap installed?"

	#Download and install Suricata
	wget $SURICATA_URL -Outfile $DOCS\suricata.msi
	start -wait msiexec.exe -ArgumentList "-i $DOCS\suricata.msi -passive"

	#Download and install rules
	wget $RULES_URL -Outfile $DOCS\rules.zip
	Expand-Archive -Path $DOCS\rules.zip -DestinationPath $DOCS
	mv $DOCS\emerging-all.rules 'C:\Program Files\Suricata\rules\'

	#Create Suricata service and start it
	cd 'C:\Program Files\Suricata\'
	.\suricata.exe -c suricata.yaml -s rules\emerging-all.rules -i $IP --service-install
	NET START Suricata
	cd $DOCS

	#Configure Wazuh to ingest the logs
	Add-Content -Path 'C:\Program Files (x86)\ossec-agent\ossec.conf' "<ossec_config>`n <localfile>`n  <log_format>json</log_format>`n  <location>C:\Program Files\Suricata\log\eve.json</location>`n </localfile>`n</ossec_config>"
	Restart-Service -Name Wazuh


    echo "`n******************** DOWNLOADING KF SENSOR HONEYPOT INSTALLER ********************`n"

    wget $KF_URL -OutFile "$ROOT\kfsense-installer.msi"

    echo "`n******************** DOWNLOADING SYSINTERNALS ********************`n"

    wget $SYSINTERNALS_URL -OutFile $DOCS\sysinternals.zip
    Expand-Archive -Path $DOCS\sysinternals.zip -DestinationPath $ROOT\sysinternals

    echo "`n******************** DOWNLOADING WORMHOLE ********************`n"
	wget $WORMHOLE_URL -OutFile $ROOT\wormhole.exe

    echo "`n******************** DOWNLOADING SHARPHOUND ********************`n"
	wget $SHARPHOUND_URL -Outfile $DOCS\sharphound.zip
    Expand-Archive -Path $DOCS\sharphound.zip -DestinationPath $ROOT\sharphound

} | Out-Default

Stop-Transcript
