###
# Jack's Sec Env Reader (Now without the login spam!!)
###

# Define the event log & event IDs for admin actions
$logName = "Security"
$eventIDs = 4670, 4720, 4722, 4732, 4728  # List of Event IDs to track

# Get the current datetime
$currentTime = Get-Date

# Calc the start time for the queries
$oneHourAgo = $currentTime.AddHours(-1)
$oneWeekAgo = $currentTime.AddDays(-7)

# Query events from the last hour
$lastHourEvents = Get-WinEvent -FilterHashtable @{
    LogName = $logName
    Id = $eventIDs
    StartTime = $oneHourAgo
} | Select-Object @{Name="Time"; Expression={($_.TimeCreated).ToString("MM/dd HH:mm")}}, 
                  Id, 
                  @{Name="ComputerName"; Expression={$_.MachineName}}, 
                  @{Name="UserName"; Expression={$_.Properties[1].Value}}, 
                  Message

# Query events from the last week
$lastWeekEvents = Get-WinEvent -FilterHashtable @{
    LogName = $logName
    Id = $eventIDs
    StartTime = $oneWeekAgo
#Exclude Last Hour
    EndTime = $oneHourAgo  # Ensure we exclude events in the last hour
} | Select-Object @{Name="Time"; Expression={($_.TimeCreated).ToString("MM/dd HH:mm")}}, 
                  Id, 
                  @{Name="ComputerName"; Expression={$_.MachineName}}, 
                  @{Name="UserName"; Expression={$_.Properties[1].Value}}, 
                  Message

# Generate report tables
$lastHourTable = $lastHourEvents | Format-Table -AutoSize | Out-String
$lastWeekTable = $lastWeekEvents | Format-Table -AutoSize | Out-String

$report = @"
Administrative Actions Report
=============================

Report generated on: $(Get-Date)

1. Administrative actions taken in the last hour:
-------------------------------------------------
$lastHourTable

2. Administrative actions taken in the last week:
-------------------------------------------------
$lastWeekTable
"@

# Output the report to the script's directory and print it.

# Get the current directory where the script is running and save the report.
$scriptDirectory = (Get-Location).Path  
$reportPath = Join-Path -Path $scriptDirectory -ChildPath "AdminActionsReport.txt"
$report | Out-File -FilePath $reportPath
Write-Output $report
