# Installing firefox. the more supporior browser than edge (why would any team use edge smh)
$firefoxInstallerUrl = "https://download.mozilla.org/?product=firefox-stub&os=win&lang=en-US"
$firefoxInstallerPath = "C:\Temp\Firefox Installer.exe"

# Download Firefox installer
Invoke-WebRequest -Uri $firefoxInstallerUrl -OutFile $firefoxInstallerPath

# Silent install
Start-Process -FilePath $firefoxInstallerPath -ArgumentList "/silent" -Wait

# Cleanup
Remove-Item -Path $firefoxInstallerPath -Force