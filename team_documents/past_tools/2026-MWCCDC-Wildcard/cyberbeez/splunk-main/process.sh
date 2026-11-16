#!/bin/bash

# Scripted by Team 9 - Employee 6

echo "Please choose an option:"
echo "1: View Current Processes & Priority"
echo "2: Change Process Priority"

read -p "Enter your choice [1 or 2]: " choice

case $choice in
	1)
		echo "You chose Option One."
		ps ax -o pid,ni,cmd
		
	2)
		echo "You chose Option Two."
		read -p "Enter a niceness value: " niceness
		read -p "Enter the process value: " process
		renice $niceness $process
	*)
		echo "Invalid choice. Run the script again to chose valid options."
		
		
		