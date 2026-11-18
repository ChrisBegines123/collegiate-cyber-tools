# setup-iis-http+https-same.ps1
# SAME content on HTTP:80 and HTTPS:443. No redirect.
# Removes 80/443 bindings from any other IIS sites (no name assumptions).

$ErrorActionPreference = "Stop"

$SiteName  = "wwwroot"
$SitePath  = "C:\inetpub\wwwroot\wwwroot"
$DnsName   = "localhost"
$HttpPort  = 80
$HttpsPort = 443

Import-Module ServerManager
Add-WindowsFeature `
  Web-Server,Web-WebServer,Web-Common-Http,Web-Static-Content,Web-Default-Doc,Web-Http-Errors,Web-Mgmt-Tools | Out-Null
Import-Module WebAdministration

if (-not (Test-Path "$SitePath\index.html")) { throw "Missing $SitePath\index.html" }

# Remove existing site if present
if (Test-Path "IIS:\Sites\$SiteName") { Remove-Website $SiteName }

# App pool (static)
if (-not (Test-Path "IIS:\AppPools\$SiteName")) { New-WebAppPool $SiteName | Out-Null }
Set-ItemProperty "IIS:\AppPools\$SiteName" -Name managedRuntimeVersion -Value ""

# Create site on HTTP 80
New-Website -Name $SiteName -PhysicalPath $SitePath -Port $HttpPort -ApplicationPool $SiteName | Out-Null

# Add HTTPS 443 binding
New-WebBinding -Name $SiteName -Protocol https -Port $HttpsPort | Out-Null

# Self-signed cert + bind to 0.0.0.0:443
$cert = Get-ChildItem Cert:\LocalMachine\My | ? { $_.Subject -eq "CN=$DnsName" } | sort NotAfter -desc | select -first 1
if (-not $cert) { $cert = New-SelfSignedCertificate -DnsName $DnsName -CertStoreLocation "Cert:\LocalMachine\My" }

if (Test-Path "IIS:\SslBindings\0.0.0.0!$HttpsPort") { Remove-Item "IIS:\SslBindings\0.0.0.0!$HttpsPort" -Force }
New-Item "IIS:\SslBindings\0.0.0.0!$HttpsPort" -Thumbprint $cert.Thumbprint | Out-Null

# Remove 80/443 bindings from any other sites
Get-Website | ForEach-Object {
  $name = $_.Name
  if ($name -ne $SiteName) {
    Get-WebBinding -Name $name -Protocol http -ErrorAction SilentlyContinue |
      Where-Object { $_.bindingInformation -like "*:${HttpPort}:*" } |
      Remove-WebBinding -ErrorAction SilentlyContinue

    Get-WebBinding -Name $name -Protocol https -ErrorAction SilentlyContinue |
      Where-Object { $_.bindingInformation -like "*:${HttpsPort}:*" } |
      Remove-WebBinding -ErrorAction SilentlyContinue
  }
}

# Firewall 80/443
$rule80  = "IIS-$SiteName-HTTP-$HttpPort"
$rule443 = "IIS-$SiteName-HTTPS-$HttpsPort"
Get-NetFirewallRule -DisplayName $rule80  -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
Get-NetFirewallRule -DisplayName $rule443 -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName $rule80  -Direction Inbound -Action Allow -Protocol TCP -LocalPort $HttpPort  | Out-Null
New-NetFirewallRule -DisplayName $rule443 -Direction Inbound -Action Allow -Protocol TCP -LocalPort $HttpsPort | Out-Null

iisreset | Out-Null
Start-Website $SiteName

Write-Host "[+] Done."
Get-Website | ft name,state,bindings,physicalPath -Auto