# Function to get the hash of the file
function Get-FileHashValue {
    param ([string]$filePath)
    
    if (Test-Path $filePath) {
        $hash = Get-FileHash $filePath | Select-Object -ExpandProperty Hash
        return $hash
    } else {
        Write-Host "File not found: $filePath"
        exit
    }
}

# Prompt the user for the file location
$filePath = Read-Host "Enter the full path of the file to monitor"

# Get the initial hash of the file
$previousHash = Get-FileHashValue -filePath $filePath
Write-Host "Initial hash: $previousHash"

# Monitoring loop
while ($true) {
    Start-Sleep -Seconds 120  # Wait for 2 minutes

    # Get the current hash of the file
    $currentHash = Get-FileHashValue -filePath $filePath

    # Compare the hash values
    $comparison = Compare-Object $previousHash $currentHash

    if ($comparison) {
        Write-Host "File has been modified."
        Write-Host "Previous hash: $previousHash"
        Write-Host "Current hash: $currentHash"
        # Update the previous hash
        $previousHash = $currentHash
    } else {
        Write-Host "No change detected in the file."
    }
}