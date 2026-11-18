function Show-HuskyBanner {
    $Art = @'
                 ___
             .-"`   `"-.
           .'           '.
          /   .-"``"-.    \
         |   /        \    |
         |  |  .--.    |   |
         |  | (o_o )   |   |
          \  \  '--'   /   /
           '. `'----'`  .'
             '-._____.-'
                 || 
    _____________||_____________
   /                              \
  /                                \
 |                                  |
 |      ________________            |
 |     /                \           |
 |    |   HUSKY ARMED    |          |
 |    |       /\         |          |
 |    |      ||====>     |          |
 |    |__________________|          |
 |                                  |
 \_________________________________/
 
    ~~~~  ~~~~~~  ~~~~  ~~~~~~
 ~~~      * .      ~~~
'@
    Write-Host $Art -ForegroundColor Yellow
}

# --- INITIAL SETUP & SHORTCUT LOGIC ---
$ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "config.txt"

$NewWidth  = 100
$NewHeight = 45

# 2. Adjust the Buffer Size first
# The Buffer must always be equal to or larger than the Window Size
$Size = $Host.UI.RawUI.WindowSize
$Buffer = $Host.UI.RawUI.BufferSize

if ($Buffer.Width -lt $NewWidth) { $Buffer.Width = $NewWidth }
if ($Buffer.Height -lt $NewHeight) { $Buffer.Height = $NewHeight }
$Host.UI.RawUI.BufferSize = $Buffer

# 3. Apply the new Window Size
$Size.Width = $NewWidth
$Size.Height = $NewHeight
$Host.UI.RawUI.WindowSize = $Size

if (-not (Test-Path -Path $ConfigPath)) {
    Clear-Host
    Show-HuskyBanner
    Write-Host "`n[ INITIAL SETUP ]" -ForegroundColor Cyan
    $Mapping = @{ 'f'='ftp'; 'w'='web'; 'a'='ad'; 's'='workstation' }
    Write-Host "f) FTP`nw) Web`na) AD`ns) Workstation"

    $Selection = ""
    while ($null -eq $Mapping[$Selection]) { $Selection = Read-Host "Enter choice" }
    $Role = $Mapping[$Selection]

    try {
        $Role | Out-File -FilePath $ConfigPath -Encoding utf8
        
        # Create Admin Shortcut on Desktop
        $WshShell = New-Object -ComObject WScript.Shell
        $ShortcutPath = Join-Path -Path ([Environment]::GetFolderPath("Desktop")) -ChildPath "Husky Armed.lnk"
        $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
        $Shortcut.TargetPath = "powershell.exe"
        $Shortcut.Arguments = "-NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        $Shortcut.WorkingDirectory = $PSScriptRoot
        $Shortcut.Save()

        # Set 'Run as Admin' bit on the shortcut
        $bytes = [System.IO.File]::ReadAllBytes($ShortcutPath)
        $bytes[21] = $bytes[21] -bor 0x20
        [System.IO.File]::WriteAllBytes($ShortcutPath, $bytes)

        Write-Host "`nSuccessfully saved '$Role'." -ForegroundColor Green
        Write-Host "Admin shortcut created on your Desktop. Drag it to your Taskbar!" -ForegroundColor Magenta
        Pause
    }
    catch { Write-Error "Setup failed: $($_.Exception.Message)" }
}

# --- MAIN NAVIGATION LOOP ---
while ($true) {
    Clear-Host
    Show-HuskyBanner
    
    $CurrentService = (Get-Content -Path $ConfigPath).Trim()
    Write-Host "`n[ SERVICE: $($CurrentService.ToUpper()) ]" -ForegroundColor Cyan
    Write-Host "Select a directory to browse:"
    Write-Host "1) All`n2) $CurrentService`nQ) Quit"
    
    $DirChoice = Read-Host "`nSelection"
    if ($DirChoice -eq "q") { break }
    if ($DirChoice -notmatch "^[1-2]$") { continue }

    $TargetDir = if ($DirChoice -eq "1") { Join-Path -Path $PSScriptRoot -ChildPath "all" } 
                 else { Join-Path -Path $PSScriptRoot -ChildPath $CurrentService }

    if (-not (Test-Path -Path $TargetDir)) {
        Write-Host "Directory '$TargetDir' missing!" -ForegroundColor Red
        Pause; continue
    }

    # --- FILE SELECTION LOOP ---
    while ($true) {
        Clear-Host
        Show-HuskyBanner
        Write-Host "`n[ BROWSING: $(Split-Path $TargetDir -Leaf) ]" -ForegroundColor Green
        
        $Files = Get-ChildItem -Path $TargetDir -Filter "*.ps1" -File
        
        for ($i = 0; $i -lt $Files.Count; $i++) {
            Write-Host "$($i + 1)) $($Files[$i].Name)"
        }
        Write-Host "B) Back to Main Menu" -ForegroundColor Yellow

        $Input = Read-Host "`nSelect a script to execute"
        
        if ($Input -eq "b") { break }

        # --- THE FIX IS HERE ---
        $Idx = 0  # Initialize the variable so [ref] has something to point to
        
        if ([int]::TryParse($Input, [ref]$Idx) -and $Idx -le $Files.Count -and $Idx -gt 0) {
            $ScriptToRun = $Files[$Idx - 1].FullName
            Write-Host "`n--- Executing $($Files[$Idx - 1].Name) ---" -ForegroundColor Cyan
            & $ScriptToRun
            Write-Host "`n--- Execution Finished ---" -ForegroundColor Cyan
            Pause
        }
        else {
            Write-Host "Invalid selection, try again." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}