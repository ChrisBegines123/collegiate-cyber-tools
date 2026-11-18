# Andrew Leuze - SCSU 2026 - Regionals

# compare.ps1 compares autorunsc.exe output against a baseline found in deps/baseline.csv and flags any new entries

param(
    [string]$AutorunsPath = ".\deps\autorunsc.exe"
)

$exclusions = @(
    "chrome.exe",
    "splunkd.exe",
    "splunkforwarder.exe",
    "windows defender",
    "microsoft edge"
    # ADD MORE EXCLUSIONS HERE
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaselineCsv = Join-Path $scriptDir ".\deps\baseline.csv"
$tempCsv = "$env:TEMP\autoruns_current.csv"

& $AutorunsPath -accepteula -a * -c -s -nobanner > $tempCsv

$baseline = Import-Csv $BaselineCsv
$current  = Import-Csv $tempCsv

$suspiciousArgs = "enc|encodedcommand|base64|http|https|download|powershell|cmd /c|mshta|rundll32|regsvr32|bitsadmin"
$userWritable   = "users\\|appdata|temp|programdata|public"
$rareCategories = "boot execute|image hijacks|appinit|known dlls|print monitors|winsock providers"

Write-Host "New autorun entries:"

function Normalize-Entry {
    param($entry)

    $category = ($entry.Category | Out-String).Trim().ToLower()
    $location = ($entry.'Entry Location' | Out-String).Trim().ToLower()
    $name     = ($entry.Entry | Out-String).Trim().ToLower()

    "$category|$location|$name"
}

$baselineIndex = @{}
foreach ($b in $baseline) {
    $baselineIndex[(Normalize-Entry $b)] = $true
}

foreach ($c in $current) {

    $key = Normalize-Entry $c

    if (-not $baselineIndex.ContainsKey($key)) {

        $launch = $c.'Launch String'
        $exe = ""
        $args = ""

        if ($launch -match '^(".*?"|\S+)\s*(.*)$') {
            $exe  = $matches[1]
            $args = $matches[2]
        } else {
            $exe = $launch
        }

        # Skip trusted programs
        $skip = $false
        foreach ($e in $exclusions) {
            if ($c.Entry -match [regex]::Escape($e) -or $exe -match [regex]::Escape($e)) {
                $skip = $true
                break
            }
        }
        if ($skip) { continue }

        # First line
        Write-Host "$($c.Category) | $($c.Entry) | $exe $args"

        # Second line: alerts
        $alerts = @()
        if ($args -match $suspiciousArgs) { $alerts += "sus args detected" }
        if ($c.'Image Path' -match $userWritable) { $alerts += "user writable path" }
        if ($c.Signer -eq "" -or $c.Signer -eq "Not verified") { $alerts += "unsigned binary" }
        if ($c.Category.ToLower() -match $rareCategories) { $alerts += "rare category" }

        if ($alerts.Count -gt 0) {
            Write-Host "-> alerts: " -NoNewline
            Write-Host ($alerts -join " | ") -ForegroundColor DarkYellow
        }

        Write-Host ""
    }
}
