# Set the path to the image file you want to open
$imagePath = "C:\cow.gif"

# Ensure the file exists
if (Test-Path $imagePath) {
    # Loop to open the image file repeatedly
    while ($true) {
        Start-Process -FilePath "rundll32.exe" -ArgumentList "C:\Program Files\Windows Photo Viewer\PhotoViewer.dll, ImageView_Fullscreen $imagePath"
        Start-Sleep -Milliseconds 500  # Optional delay between openings
    }
} else {
    Write-Host "Image file not found at $imagePath"
}