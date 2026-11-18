# 1. Define the path to the 'beginning' folder relative to this script
$ScriptsFolder = Join-Path -Path $PSScriptRoot -ChildPath "beginning"

# 2. Check if the folder actually exists
if (Test-Path -Path $ScriptsFolder) {
    Write-Host "Checking for startup scripts in: $ScriptsFolder" -ForegroundColor Cyan
    
    # 3. Retrieve all PowerShell files (.ps1)
    $Scripts = Get-ChildItem -Path $ScriptsFolder -Filter "*.ps1" -File | Sort-Object Name
    
    if ($Scripts.Count -eq 0) {
        Write-Host "No scripts found in the 'beginning' directory." -ForegroundColor Yellow
    } else {
        foreach ($Script in $Scripts) {
            Write-Host "`n>>> Executing: $($Script.Name)" -ForegroundColor Green
            Write-Host "------------------------------------------" -ForegroundColor DarkGray
            
            try {
                # The dot-source operator (.) runs the script in the current scope
                # The call operator (&) runs it in a child scope. We'll use & for isolation.
                & $Script.FullName
            }
            catch {
                Write-Error "Failed to execute $($Script.Name): $($_.Exception.Message)"
            }
        }
        Write-Host "`nAll scripts processed." -ForegroundColor Cyan
    }
}
else {
    Write-Host "Error: The folder '$ScriptsFolder' was not found." -ForegroundColor Red
}