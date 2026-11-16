#!/bin/bash
# PUT VIRUSTOTAL API KEY INSIDE THE QUOTES BELOW
K="PASTE_YOUR_API_KEY_HERE"
F=$1
H=$(sha256sum "$F" | cut -d' ' -f1)

# Check VirusTotal
R=$(curl -s -H "x-apikey:$K" "https://www.virustotal.com/api/v3/files/$H")

# 1. Success check (If we see "malicious" stats, it worked)
if echo "$R" | grep -q '"malicious":'; then
  # Extract the count safely
  M=$(echo "$R" | grep -Eo '"malicious": *[0-9]+' | head -1 | grep -o '[0-9]*')
  
  if [ "$M" -gt 0 ]; then
    echo -e "\033[31mMALICIOUS ($M engines)\033[0m"
  else
    echo -e "\033[32mCLEAN (0 engines)\033[0m"
  fi
  echo "Link: https://www.virustotal.com/gui/file/$H"

# New file check (If not found, upload)
elif [[ $R == *"NotFoundError"* ]]; then
  echo "File unknown. Uploading..."
  U=$(curl -s -H "x-apikey:$K" -F "file=@$F" "https://www.virustotal.com/api/v3/files")
  ID=$(echo "$U" | grep -Eo '"id": *"[^"]*"' | head -1 | cut -d'"' -f4)
  echo -e "\n\033[33mUpload queued! Track progress here:\033[0m"
  echo "https://www.virustotal.com/gui/analysis/$ID"

# Error Check
else
  MSG=$(echo "$R" | grep -Eo '"message": *"[^"]*"' | head -1 | cut -d'"' -f4)
  if [ -z "$MSG" ]; then MSG="$R"; fi
  echo -e "\033[31mAPI Error: $MSG\033[0m"
fi
