#Get all scheduled tasks

$tasks = Get-ScheduledTask

#Initialize an array to store task details

$taskDetails = @()

#Loop through each task to get the user information

foreach ($task in $tasks) {
	$taskInfo = [PSCustomObject]@{
		TaskName = $task.TaskName
		UserId = (Get-ScheduledTask -TaskName $task.TaskName).Principal.UserId
	}
	$taskDetails += $taskInfo
}

$taskDetails | Format-Table -AutoSize

pause

#Get-ScheduledTask: Retrieves all scheduled tasks on the system.
#Get-ScheduledTaskInfo: Retrieves detailed information about each scheduled task, including the user ID.
#[PSCusomObject]: Creates a custom objet to store task name and user ID.
#Format-Table -AusoSize: Formats the output in a readable table.

