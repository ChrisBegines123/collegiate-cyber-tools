param([Alias("p", "path")] $ROOT = "C:\Users\$Env:UserName\Desktop\PS-LOGS", [Alias("b", "baseline")] $BASE = $false)

$time = Get-Date -Format "HH-mm-ss"
$fileName = ""

echo "`nCreating log file..."
if ($BASE) {
    $fileName = "SMB-SHARES-BASELINE.txt"
}
else {
    $fileName = "SMB-SHARES-$time.txt"
}

New-Item -Path $ROOT\$fileName -Force -ItemType "file"

if (Test-Path -Path $ROOT\SMB-DIFFS.txt) {
    Remove-Item $ROOT\SMB-DIFFS.txt
}

. {
    Get-SmbShare
    Get-SmbShare | Get-SmbShareAccess

} | Tee-Object $ROOT\$filename

if (-Not $BASE) {
    . {
        diff -DifferenceObject (Get-Content -Path $ROOT\$filename) -ReferenceObject (Get-Content -Path $ROOT\SMB-SHARES-BASELINE.txt)
    } | Tee-Object $ROOT\SMB-DIFFS.txt
}