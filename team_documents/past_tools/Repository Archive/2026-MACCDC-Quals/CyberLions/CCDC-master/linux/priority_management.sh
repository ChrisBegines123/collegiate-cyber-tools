#!/bin/bash

view_processes() {
    echo "Current Processes and Priorities:"
    ps -eo pid,ni,pri,comm --sort=-ni | head -n 20
}

change_priority() {
    read -p "Enter the PID of the process: " pid
    read -p "Enter the new nice value (-20 to 19): " nice_value

    if ! [[ "$nice_value" =~ ^-?[0-9]+$ ]] || [ "$nice_value" -lt -20 ] || [ "$nice_value" -gt 19 ]; then
        echo "Invalid nice value. Please enter a number between -20 and 19."
        return
    fi

    sudo renice "$nice_value" "$pid"
    echo "Priority changed for process $pid"
}

while true; do
    echo "Process Priority Management"
    echo "1. View Current Processes and their Priorities"
    echo "2. Change the Priority of a Process"
    echo "3. Exit"
    read -p "Enter your choice (1-3): " choice

    case $choice in
        1) view_processes ;;
        2) change_priority ;;
        3) exit 0 ;;
        *) echo "Invalid choice. Please enter 1, 2, or 3." ;;
    esac

    echo
done
