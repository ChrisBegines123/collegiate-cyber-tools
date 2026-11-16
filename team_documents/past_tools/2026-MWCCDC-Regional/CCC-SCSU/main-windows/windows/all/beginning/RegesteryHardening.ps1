$ErrorActionPreference = "Continue"
function Set-RegKey {
    param (
        [string]$Path,
        [string]$Name,
        [string]$Value,
        [string]$Type = "DWord",
        [string]$Description
    )
    Write-Host "Setting $Description..." -NoNewline
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        Write-Host " [OK]" -ForegroundColor Green
    }
    catch {
        Write-Host " [ERROR]" -ForegroundColor Red
        Write-Error $_.Exception.Message
    }
}

Set-RegKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DNSClient" -Name "EnableMulticast" -Value 0 -Description "LLMNR (Disable Multicast)"
Set-RegKey -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp" -Name "DisableWpad" -Value 1 -Description "WPAD (Disable Auto-Proxy)"
Set-RegKey -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -Value 0xff -Description "IPv6 (Disable Components)"
Set-RegKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\ScriptedDiagnostics" -Name "EnableDiagnostics" -Value 0 -Description "MSDT (Follina Fix)"
Set-RegKey -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoDriveTypeAutoRun" -Value 255 -Description "Autoplay (Disable All Drives)"
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WinHttpAutoProxySvc" -Name "Start" -Value 4 -Force -ErrorAction SilentlyContinue
Set-RegKey -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LmCompatibilityLevel" -Value 5 -Description "NTLM Hardening (Level 5)"
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Lsa\MSV1_0" -Name "RestrictIncomingNTLMTraffic" -Value 2
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Lsa\MSV1_0" -Name "RestrictSendingNTLMTraffic" -Value 2