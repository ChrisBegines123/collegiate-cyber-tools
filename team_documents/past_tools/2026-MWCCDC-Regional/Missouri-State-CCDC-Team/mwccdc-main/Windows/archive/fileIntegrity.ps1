# ==============================================================================
# Script Name : .\fileIntegrity.ps1
# Description : Monitors files for changes and maintains a baseline hash.
# Author      : Tyler Olson
# Version     : 1.0
# ==============================================================================
# Usage       : .\fileIntegrity.ps1 
# ==============================================================================

# Variable configuration
$file = "./files" 
$Running = $true # used for persistence of the application
$logging = $false
$progResponse = " "


function Request-Choices() {
    # Write the initial choices to the console
    Write-Host ""
    Write-Host "What would you like to do?"
    Write-Host "A) Collect new baseline"
    Write-Host "B) Begin monitoring files with saved baseline"
    Write-Host "C) Change Settings"
    Write-Host "exit) exit program"
    $response = Read-Host -Prompt "Please enter 'A' or 'B' or 'C'"
    Write-Host ""
    return $response
}

# Measure-File-Hash gathers the file hash
# for the file placed in the arguement

function Measure-File-Hash($filepath) {
    $filehash = Get-FileHash -Path $filepath -Algorithm SHA512
    return $filehash
}

function Request-Directory () {

    # Use this to change default directory of files
    $run = $true
    while ($run) {
        $reply = Read-Host -Prompt "What is the file path you would like to use?"
        if (Test-Path -Path $reply) {
            Write-Host "File successfully inputed." -ForegroundColor Green
            return $reply
        }
        elseif ($reply -eq "exit".ToUpper()) {
            $run = $false
        }
        else {
            Write-Host "Error, File not valid please try again"
        }
    }
}

function Write-Settings () {
    Write-host ""
    Write-host "Settings menu:"
    Write-host "Select the setting to change:"
    Write-host "A) File path for monitored files"
    Write-host "B) Logging"
    Write-host ""

    $reply = Read-Host -Prompt "Please enter 'A', 'B', or 'C'"
    return $reply
}

function Write-Logging () {
    Write-Host ""
    Write-Host "Logging will write to the file log.txt in the main folder of the application."
    Write-Host "Would you like to turn logging on? "
    Write-Host ""

    $reply = Read-Host -Prompt "Enter 'Y' or 'N': "

    if ($reply -eq "Y".ToUpper()) {
        return $true
    }

    else {
        return $false
    }
}


function Watch-File ($logging, $response) {
    # Define the variables to be used in this function
      $fileHashDictionary = @{}
      $AlertDictionary = @{}
  
      #Notify the user the program has started looping and how to exit
      Write-Host "Starting the monitoring program. Stop the program with 'Ctrl +C'" -ForegroundColor Green
  
      
      #load file|hash from baseline.txt and store in the dictionary
      $filePathsAndHashes = Get-Content -Path .\baseline.txt
      foreach ($f in $filePathsAndHashes) {
        $fileHashDictionary.add($f.Split("|")[0].Trim(), $f.Split("|")[1].Trim())
      }
  
      #Watch loop starts
      while ($true) {
        Start-Sleep -Seconds 1
        $files = Get-ChildItem -Path .\files
  
        # for each file, calculate the hash and write to baseline.txt
          foreach ($f in $files) {
           $hash = Measure-File-Hash $f.FullName
  
            #notify if a new file has been created
            if ($null -eq $fileHashDictionary[$hash.Path]) {
              # A new file has been created
              Write-Host "$($hash.Path) has been created!" -ForegroundColor Green
  
              # Adds to the directory to avoid repeat hits
              $fileHashDictionary.add($hash.Path, $Hash.Hash)
  
              #If logging adds it to the log
              if ($logging -eq $true) {
                  "$(Get-Date -Format o) | $($hash.Path) has been created!" | Out-File -FilePath .\log.txt -Append
              }
            }
  
              #If file exists in the database already, it will run other checks
              # otherwise it will exit and move to the next loop.
    
              else {
                   # Check to see if the hash does not match hash stored
                  if ($fileHashDictionary[$hash.Path] -eq $($hash.Hash)) {
                      # Path has not changed nothing will occur
                    }
  
                  else {
                      # file has been comprimised!
                      Write-Host "$($hash.Path) Has been changed!" -ForegroundColor Yellow
  
                      # Adds to the directory to avoid repeat hits
                      $fileHashDictionary[$hash.Path] = $hash.Hash
  
                      if ($logging -eq $true) {
                        "$(Get-Date -Format o) | $($hash.Path) has been changed!" | Out-File -FilePath .\log.txt -Append
                      }
                    }
                  }
                  
                # Notify if a file has been deleted
                  
                foreach ($key in $fileHashDictionary.Keys) {
                  $baselineFileStillExists = Test-Path -Path $key
                  if ((-Not $baselineFileStillExists) -and ($null -eq $AlertDictionary[$key])) {
                      #One of the baseline files have been deleted notify user
                      Write-Host "$($key) has been deleted!" -ForegroundColor DarkMagenta
  
                      $AlertDictionary[$key] = $fileHashDictionary[$key]
  
                      if ($logging -eq $true) {
                        "$(Get-Date -Format o) | $($key) has been deleted!" | Out-File -FilePath .\log.txt -Append
                    }
                  }
              } # stopping looping through keys
          } # end of loop through files
      } # End of while
    } # End of Watch-File function



while($Running) {
    # Calls the function to request the choices
    $response = Request-Choices

    # Checks if the response is "A"
    # If so will start to create the baseline for the monitoring
    if ($response -eq "A".ToUpper()) {
        $count = 0
        #Delete baseline.txt if it already exists
        $baselineExists = Test-Path -Path .\baseline.txt
        if($baselineExists) {
            # Delete the baseline
            Remove-Item -Path .\baseline.txt
        }
        
        # Calculate hash from the target files and store in baseline
        Write-Host "Calculating Hashes..." -ForegroundColor Cyan

        #Collect all the files in the target folder
        $files = Get-ChildItem -Path $file

        # For each file, calculate the hash and write it to baseline.txt
        foreach ($f in $files) {
            $hash = Measure-File-Hash $f.FullName
            "$($hash.Path) | $($hash.hash)" | Out-File -FilePath .\baseline.txt -Append
            $count +=1
        }
        Write-Host "Hashes calculated, $($count) total files hashed." -ForegroundColor Green
    } 



    elseif ($response -eq "B".ToUpper()) {
        #Calls the function Watch-File in the file "watch.ps1" 
        Watch-File $logging, $progResponse
    }

    <#
    Check and see if the response is "C" 
    If so will change the directory the program will monitor
    #>

    elseif ($response -eq "C".ToUpper()) {
        
        $reply = Write-Settings
        
        if ($reply -eq "A".ToUpper()) { 
            <# Use this to change default directory of files #>
            $file = Request-Directory
        }

        elseif ($reply -eq "B".ToUpper()) {
            <# logging #>
            $logging = Write-Logging
        }

    }

    # Check to see if the response was "exit"
    # This will exit the running program.

    elseif ($response -eq "exit".ToUpper()) {
        Write-Host "Exiting program"
        $Running = $false
    }



    else {
        Write-host "Thats not a valid answer!" -ForegroundColor Red -BackgroundColor White
        Write-host "Please input either 'A' or 'B'"
    }
}