## Introduction

This dir is for windows hardening scripts. A couple of quick notes:
- This script only supports Windows Server 2016 or above (Windows 10 or later equivalent) currently
- Entrypoint is start.bat
- The powershell scripts may be blocked by execution policy. There have been several measures taken to eliminate this error, but they work on some machines and not others. If the scripts get blocked, changing something small, saving the file, and changing it back should get around execution policy

## Installation

Installing and running is as simple as getting a copy of this repo and running start.bat.

### Quick Install
Run these commands in powershell:
```
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;
$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest https://github.com/archHavik/Useful-Scripts/archive/refs/heads/main.zip -Outfile Useful-Scripts.zip;
Expand-Archive -Path Useful-Scripts.zip -DestinationPath Useful-Scripts;
```

Start the script with:
```
cd Useful-Scripts\Useful-Scripts-main\windows-hardening\;
.\start.bat;
```

## Features
- Enables Firewall, Windows Defender, and Windows Update
- Changes current user's password and creates a backup user 'printer'
- Disables insecure protocols and services such as SMBv1, RDP, and the Printer Spooler Service
- Installs useful tools:
	- Wazuh Agent
	- KFSensor honeypot
	- Sysinternals suite
	- Registry manager
	- HardeningKitty
- Sets a custom login banner
- Logs all commands run by the script to the Desktop folder of the current user
- Includes a copy of the [IronXP repo](https://github.com/d3coder/IronXP) for a small amount of Windows XP hardening
