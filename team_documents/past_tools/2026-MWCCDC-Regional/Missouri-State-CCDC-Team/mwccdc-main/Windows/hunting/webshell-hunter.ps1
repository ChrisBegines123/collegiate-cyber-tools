<#
.SYNOPSIS
  Scan folders for suspicious PHP files likely to be web shells or backdoors.

.DESCRIPTION
  Recursively searches for *.php files under a provided path (default: current directory).
  For each file it applies multiple heuristic checks (regexes for suspicious functions,
  encoding/obfuscation patterns, long base64 blobs, dynamic eval usage) and computes a
  weighted score. Files above the threshold are output sorted by score, with matched
  signatures and a snippet for quick triage.

.PARAMETER Path
  Root path to scan. Default: current directory.

.PARAMETER Threshold
  Minimum score to show as suspicious (default: 5).

.PARAMETER ExportCsv
  Optional path to export full results as CSV.

.PARAMETER MaxDepth
  Limit recursion depth (default: unlimited).

.EXAMPLE
  .\Find-PHP-ReverseShells.ps1 -Path "C:\inetpub\wwwroot" -Threshold 6 -ExportCsv C:\temp\php-scan.csv
#>

param(
    [string]$Path = ".",
    [int]$Threshold = 5,
    [string]$ExportCsv = "",
    [int]$MaxDepth = 0
)

function Get-ShannonEntropy {
    param([string]$s)
    if ([string]::IsNullOrEmpty($s)) { return 0 }
    $freq = @{}
    foreach ($c in $s.ToCharArray()) {
        if ($freq.ContainsKey($c)) { $freq[$c]++ } else { $freq[$c] = 1 }
    }
    $len = $s.Length
    $entropy = 0.0
    foreach ($k in $freq.Keys) {
        $p = $freq[$k] / $len
        $entropy -= $p * [math]::Log($p, 2)
    }
    return [math]::Round($entropy, 3)
}

# Weighted suspicious patterns (regex, weight, reason)
$patterns = @(
    @{re = '(?i)\beval\s*\(';           w=5; reason='eval(...) usage' },
    @{re = '(?i)base64_decode\s*\(';   w=4; reason='base64_decode(...)' },
    @{re = '(?i)gzinflate\s*\(';       w=4; reason='gzinflate/gzuncompress (compressed payload)' },
    @{re = '(?i)preg_replace\s*\([^,]+,.*\/e'; w=4; reason='preg_replace with /e (executes)' },
    @{re = '(?i)\bassert\s*\(';        w=4; reason='assert(...) used to execute code' },
    @{re = '(?i)\bshell_exec\s*\(';    w=5; reason='shell_exec(...)' },
    @{re = '(?i)\bexec\s*\(';          w=5; reason='exec(...)' },
    @{re = '(?i)\bpassthru\s*\(';      w=5; reason='passthru(...)' },
    @{re = '(?i)\bsystem\s*\(';        w=5; reason='system(...)' },
    @{re = '(?i)\bproc_open\s*\(';     w=6; reason='proc_open (advanced process exec)' },
    @{re = '(?i)\bpopen\s*\(';         w=5; reason='popen(...)' },
    @{re = '(?i)\b`[^`]+`';            w=5; reason='backtick execution' },
    @{re = '(?i)\bpassthru\b';         w=3; reason='passthru token (lower weight duplicate safe-check)' },
    @{re = '(?i)\bcreate_function\s*\('; w=4; reason='create_function (dynamic eval-like)' },
    @{re = '(?i)\bpreg_match\b.*\$_(GET|POST|REQUEST|COOKIE)'; w=2; reason='pattern using superglobals' },
    @{re = '(?i)\$_(GET|POST|REQUEST)\s*\[.*\]'; w=2; reason='use of superglobals (user input)' },
    @{re = '(?i)eval\s*\(\s*base64_decode'; w=8; reason='eval(base64_decode(...)) (classic web shell)' },
    @{re = '(?i)assert\s*\(\s*base64_decode'; w=8; reason='assert(base64_decode(...))' },
    @{re = '(?i)preg_replace\s*\(\s*.*base64_decode'; w=7; reason='preg_replace with base64_decode' },
    @{re = '(?i)str_rot13\s*\(';        w=3; reason='rot13 obfuscation' },
    @{re = '(?i)chr\(\s*\d+\s*\)\s*\.'; w=3; reason='chr(###) concatenation (obfuscation)' },
    @{re = '(?i)[A-Za-z0-9+/=]{100,}';  w=4; reason='long base64-like blob' }
)

# Helper to get snippet lines around first match
function Get-Snippet {
    param($lines, $matchLineIndex, $context=3)
    $start = [math]::Max(0, $matchLineIndex - $context)
    $end = [math]::Min($lines.Count - 1, $matchLineIndex + $context)
    return ($lines[$start..$end] -join "`n")
}

Write-Verbose "Starting scan from: $Path"
$results = @()

# Get files with optional MaxDepth support
if ($MaxDepth -gt 0) {
    $files = Get-ChildItem -Path $Path -Recurse -File -Filter *.php -ErrorAction SilentlyContinue |
             Where-Object { ($_.FullName -split [IO.Path]::DirectorySeparatorChar).Count -le (($Path -split [IO.Path]::DirectorySeparatorChar).Count + $MaxDepth) }
} else {
    $files = Get-ChildItem -Path $Path -Recurse -File -Filter *.php -ErrorAction SilentlyContinue
}

foreach ($f in $files) {
    try {
        $content = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop
    } catch {
        # if reading failed (permission/binary), skip with a note
        $results += [PSCustomObject]@{
            Path = $f.FullName
            Score = 0
            Matches = "UNREADABLE: $($_.Exception.Message)"
            Entropy = 0
            Snippet = ""
            SizeBytes = $f.Length
        }
        continue
    }

    $score = 0
    $found = @()

    # Per-pattern matching
    foreach ($p in $patterns) {
        $matches = ([regex]::Matches($content, $p.re)).Count
        if ($matches -gt 0) {
            $score += $p.w * $matches
            $found += ,@{pattern=$p.re; count=$matches; reason=$p.reason}
        }
    }

    # Detect usage of backdoor HTTP callback patterns (sockets)
    if ($content -match '(?i)fsockopen\s*\(|stream_socket_client\s*\(') {
        $score += 6
        $found += ,@{pattern='socket_connect'; count=1; reason='fsockopen/stream_socket_client (outbound socket)' }
    }

    # Detect suspicious file write / chmod (webshell may write files or set permission)
    if ($content -match '(?i)file_put_contents\s*\(|fopen\s*\(|chmod\s*\(') {
        $score += 2
        $found += ,@{pattern='file_write_chmod'; count=1; reason='file operations (possible persistence)' }
    }

    # Long continuous string (likely encoded payload). Check for base64-esque runs with length > 150
    $base64runs = [regex]::Matches($content, '[A-Za-z0-9+/=]{150,}')
    if ($base64runs.Count -gt 0) {
        $score += 5 * $base64runs.Count
        $found += ,@{pattern='long_base64_blob'; count=$base64runs.Count; reason='very long base64-like strings' }
    }

    # Entropy check on the whole file content (higher entropy may indicate encoded content)
    $entropy = Get-ShannonEntropy $content
    if ($entropy -ge 4.2) {
        # adjust weight by how high it is
        $entWeight = [math]::Round(($entropy - 4.0) * 2.5, 1)
        $score += $entWeight
        $found += ,@{pattern='high_entropy'; count=1; reason="entropy $entropy (possible encoding/obfuscation)"}
    }

    # Get first match index for snippet
    $lines = $content -split "`r?`n"
    $matchIndex = -1
    foreach ($p in $found) {
        try {
            $m = [regex]::Match($content, $p.pattern)
            if ($m.Success) {
                # find approximate line index
                $charIndex = $m.Index
                # accumulate chars until we reach charIndex to find line number
                $acc = 0; $li = 0
                for ($li=0; $li -lt $lines.Count; $li++) {
                    $acc += $lines[$li].Length + 1
                    if ($acc -gt $charIndex) { break }
                }
                $matchIndex = $li
                break
            }
        } catch { }
    }
    if ($matchIndex -eq -1) { $matchIndex = 0 }

    $snippet = Get-Snippet -lines $lines -matchLineIndex $matchIndex -context 4

    $results += [PSCustomObject]@{
        Path = $f.FullName
        Score = [math]::Round($score,2)
        Matches = ($found | ForEach-Object { "$($_.reason) (matched: $($_.count))" }) -join "; "
        Entropy = $entropy
        Snippet = $snippet
        SizeBytes = $f.Length
    }
}

# Sort by score desc
$sorted = $results | Sort-Object -Property @{Expression={$_.Score};Descending=$true}, @{Expression={$_.Entropy};Descending=$true}

# Show results above threshold
$flagged = $sorted | Where-Object { $_.Score -ge $Threshold -and $_.Path -ne $null }

if ($flagged.Count -eq 0) {
    Write-Output "No files detected above threshold ($Threshold). Top findings (if any) are listed below."
    $top = $sorted | Select-Object -First 10
    $top | Format-Table @{Label='Score';Expression={$_.Score}}, @{Label='Entropy';Expression={$_.Entropy}}, @{Label='Path';Expression={$_.Path}} -AutoSize
} else {
    Write-Output "Suspicious files (score >= $Threshold):"
    $flagged | Format-Table @{Label='Score';Expression={$_.Score}}, @{Label='Entropy';Expression={$_.Entropy}}, @{Label='Path';Expression={$_.Path}} -AutoSize

    # show snippets for top N
    $showTop = $flagged | Select-Object -First 10
    foreach ($item in $showTop) {
        "`n-----`nPath: $($item.Path)`nScore: $($item.Score)   Entropy: $($item.Entropy)`nMatches: $($item.Matches)`nSnippet:`n$($item.Snippet)`n-----`n"
    }
}

# Export CSV optionally
if ($ExportCsv) {
    $sorted | Select-Object Path, Score, Entropy, SizeBytes, Matches | Export-Csv -Path $ExportCsv -NoTypeInformation -Force
    Write-Output "Exported full results to: $ExportCsv"
}
