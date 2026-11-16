# Set the message and number of popups
$message = "Your system has been compromised!"
$popupCount = 10  # Adjust this number as needed

# Loop to create multiple popups
for ($i = 1; $i -le $popupCount; $i++) {
    [System.Windows.Forms.MessageBox]::Show($message, "Warning", 'OK', 'Warning')
    Start-Sleep -Milliseconds 500  # Slight delay between popups
}