# ===============================
# CCDC IIS HTTPS Redirect Script
# ===============================

Write-Host "=== IIS URL Rewrite + HTTPS Redirect Setup ===" -ForegroundColor Cyan

# Check for admin
if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Run this script as Administrator."
    exit 1
}

Import-Module WebAdministration



# -------------------------------
# Step 1: Install URL Rewrite
# -------------------------------
$rewriteInstalled = Get-WebGlobalModule | Where-Object { $_.Name -eq "RewriteModule" }

if (-not $rewriteInstalled) {
    Write-Host "[*] URL Rewrite not found. Downloading..." -ForegroundColor Yellow

    $msiUrl = "https://download.microsoft.com/download/D/D/9/DD9B77C9-4C6B-4C5B-A6E0-6C7D64CFA6A2/rewrite_amd64_en-US.msi"
    $msiPath = "$env:TEMP\rewrite.msi"

    Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing

    Write-Host "[*] Installing URL Rewrite..." -ForegroundColor Yellow
    Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /qn /norestart" -Wait

    Write-Host "[+] URL Rewrite installed." -ForegroundColor Green
} else {
    Write-Host "[+] URL Rewrite already installed." -ForegroundColor Green
}

# -------------------------------
# Step 2: Ask for IIS Site
# -------------------------------
Write-Host "`nAvailable IIS Sites:" -ForegroundColor Cyan
Get-Website | Select Name

$siteName = Read-Host "`nEnter the IIS Site Name EXACTLY as shown above"

if (-not (Test-Path "IIS:\Sites\$siteName")) {
    Write-Error "Site '$siteName' not found."
    exit 1
}

# -------------------------------
# Step 3: Add HTTPS Redirect Rule
# -------------------------------
Write-Host "[*] Creating HTTP -> HTTPS redirect rule..." -ForegroundColor Yellow

$ruleName = "HTTP to HTTPS Redirect"

$existingRule = Get-WebConfiguration `
    -pspath "IIS:\Sites\$siteName" `
    -filter "system.webServer/rewrite/rules/rule" |
    Where-Object { $_.Name -eq $ruleName }

if ($existingRule) {
    Write-Host "[!] Redirect rule already exists. Skipping." -ForegroundColor Yellow
    exit 0
}

Add-WebConfigurationProperty `
    -pspath "IIS:\Sites\$siteName" `
    -filter "system.webServer/rewrite/rules" `
    -name "." `
    -value @{
        name = $ruleName
        patternSyntax = "Regular Expressions"
        stopProcessing = "true"
    }

Set-WebConfigurationProperty `
    -pspath "IIS:\Sites\$siteName" `
    -filter "system.webServer/rewrite/rules/rule[@name='$ruleName']/match" `
    -name "url" `
    -value "(.*)"

Add-WebConfigurationProperty `
    -pspath "IIS:\Sites\$siteName" `
    -filter "system.webServer/rewrite/rules/rule[@name='$ruleName']/conditions" `
    -name "." `
    -value @{
        input = "{HTTPS}"
        pattern = "off"
    }

Set-WebConfigurationProperty `
    -pspath "IIS:\Sites\$siteName" `
    -filter "system.webServer/rewrite/rules/rule[@name='$ruleName']/action" `
    -name "type" `
    -value "Redirect"

Set-WebConfigurationProperty `
    -pspath "IIS:\Sites\$siteName" `
    -filter "system.webServer/rewrite/rules/rule[@name='$ruleName']/action" `
    -name "url" `
    -value "https://{HTTP_HOST}/{R:1}"

Set-WebConfigurationProperty `
    -pspath "IIS:\Sites\$siteName" `
    -filter "system.webServer/rewrite/rules/rule[@name='$ruleName']/action" `
    -name "redirectType" `
    -value "Permanent"

Write-Host "[+] HTTPS redirect enabled for site: $siteName" -ForegroundColor Green

Write-Host "`nTest with: http://<hostname> -> https://<hostname>" -ForegroundColor Cyan
