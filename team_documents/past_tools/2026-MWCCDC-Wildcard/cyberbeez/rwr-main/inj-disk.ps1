#Script to Measure Disk Usage



#Threshold in Percentage:

$Thresh = .90

# Get Current Disk Space:

$Used = Get-PSDrive / | Select-Object Used | Select -ExpandProperty Used



$Free = Get-PSDrive / | Select-Object Free | Select -Expandproperty Free



$Full = $Used + $Free



$Perc = $Used / $Full



echo $Perc" is the percent."

# Check if Disk Usage Exceed Threshold

if ($Perc -gt $Thresh) {



	# Report if exceeds limits

		echo "Usage has exceeded usage threshold!"

	# Function could be extended here for more actions

}else{

# Else Report That Usage Does Not Exceed Threshold

		echo "Usage is within usage threshhold!"

}

