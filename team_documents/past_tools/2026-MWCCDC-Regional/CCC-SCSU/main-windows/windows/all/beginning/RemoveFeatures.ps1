$ErrorActionPreference = "Continue"
function Remove-Feature {
    param (
        [string]$FeatureName,
        [string]$Description
    )
    Write-Host "Removing $Description ($FeatureName)..." -NoNewline
    
    try {
        # Check if feature is actually installed first to avoid unnecessary errors
        $feat = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue
        if ($feat.State -eq "Enabled") {
            Disable-WindowsOptionalFeature -Online -FeatureName $FeatureName -NoRestart -ErrorAction Stop | Out-Null
            Write-Host " [REMOVED]" -ForegroundColor Green
        }
        else {
            Write-Host " [ALREADY DISABLED]" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host " [ERROR]" -ForegroundColor Red
        Write-Error $_.Exception.Message
    }
}

Remove-Feature -FeatureName "MicrosoftWindowsPowerShellV2Root" -Description "PowerShell v2.0"
Remove-Feature -FeatureName "SMB1Protocol" -Description "SMBv1 Protocol"
Remove-Feature -FeatureName "Telnet-Client" -Description "Telnet Client"
Remove-Feature -FeatureName "Telnet-Server" -Description "Telnet Server"    