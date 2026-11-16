# extract-wwwroot.ps1
$ErrorActionPreference = "Stop"

$ZipUrl   = "https://raw.githubusercontent.com/4rji/dotfiles/a4faf1daceb10c2d7f6f99b8facbd6b05150e0a1/wwwroot.zip"
$BasePath = "C:\inetpub\wwwroot"
$DestPath = "C:\inetpub\wwwroot\wwwroot"

# clean old
if (Test-Path $DestPath) {
    Remove-Item $DestPath -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $BasePath | Out-Null

# download
$tmpZip = "$env:TEMP\wwwroot.zip"
Invoke-WebRequest -Uri $ZipUrl -OutFile $tmpZip

# extract
Expand-Archive -Path $tmpZip -DestinationPath $BasePath -Force
Remove-Item $tmpZip -Force

# normalize structure
# after extract we expect: C:\inetpub\wwwroot\wwwroot\index.html
if (-not (Test-Path "$DestPath\index.html")) {
    throw "index.html not found at $DestPath"
}

Write-Host "[+] Extracted correctly to $DestPath"
dir $DestPath
