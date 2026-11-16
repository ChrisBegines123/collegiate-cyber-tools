#!/bin/bash
#
# Background Script Runner with Logging
# This script runs any script in the background and logs its output to a directory.
#
# Usage: ./run_background.sh [script_path] [script_args...]
#        ./run_background.sh  (shows interactive menu)
# Example: ./run_background.sh /opt/ccdc-tools/download_tools.sh
# Example: ./run_background.sh ./enable_logging.sh --verbose
#

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default log directory
LOG_DIR="${LOG_DIR:-/var/log/ccdc/background}"

# Initialize script path and arguments
SCRIPT_PATH=""
SCRIPT_ARGS=()

# Function to show interactive menu
show_menu() {
    echo "=========================================="
    echo "  CCDC Background Script Runner"
    echo "=========================================="
    echo ""
    echo "Available scripts:"
    echo ""
    
    # Find all .sh files in the script directory (excluding this script)
    local scripts=()
    local index=1
    
    while IFS= read -r -d '' script; do
        local script_name=$(basename "$script")
        if [ "$script_name" != "run_background.sh" ]; then
            scripts+=("$script")
            printf "  %2d) %s\n" "$index" "$script_name"
            ((index++))
        fi
    done < <(find "$SCRIPT_DIR" -maxdepth 1 -name "*.sh" -type f -print0 | sort -z)
    
    echo ""
    echo "  0) Exit"
    echo ""
    echo "=========================================="
    echo -n "Select a script to run in background: "
    
    read -r choice
    
    # Validate input
    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        echo "Invalid selection. Please enter a number." >&2
        return 1
    fi
    
    if [ "$choice" -eq 0 ]; then
        echo "Exiting..."
        exit 0
    fi
    
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#scripts[@]}" ]; then
        echo "Invalid selection. Please choose a number between 1 and ${#scripts[@]}." >&2
        return 1
    fi
    
    # Get selected script (array is 0-indexed)
    local selected_index=$((choice - 1))
    local selected_script="${scripts[$selected_index]}"
    
    echo ""
    echo "Selected: $(basename "$selected_script")"
    echo -n "Enter additional arguments (or press Enter for none): "
    read -r additional_args
    
    # Set global variables
    SCRIPT_PATH="$selected_script"
    
    # Parse additional arguments into array
    if [ -n "$additional_args" ]; then
        # Use eval to properly handle quoted arguments
        eval "set -- $additional_args"
        SCRIPT_ARGS=("$@")
    else
        SCRIPT_ARGS=()
    fi
}

# Check if script path is provided
if [ $# -lt 1 ]; then
    # No arguments provided, show interactive menu
    show_menu || exit 1
    if [ -z "$SCRIPT_PATH" ]; then
        echo "Error: No script selected." >&2
        exit 1
    fi
else
    # Script path provided as argument
    SCRIPT_PATH="$1"
    shift  # Remove script path from arguments, remaining args are for the script
    SCRIPT_ARGS=("$@")
fi

# Validate script exists and is executable
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "Error: Script not found: $SCRIPT_PATH" >&2
    exit 1
fi

if [ ! -x "$SCRIPT_PATH" ]; then
    echo "Warning: Script is not executable. Attempting to make it executable..." >&2
    chmod +x "$SCRIPT_PATH" || {
        echo "Error: Failed to make script executable" >&2
        exit 1
    }
fi

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR" || {
    echo "Error: Failed to create log directory: $LOG_DIR" >&2
    exit 1
}

# Generate log file name based on script name and timestamp
SCRIPT_NAME=$(basename "$SCRIPT_PATH" .sh)
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}_${TIMESTAMP}.log"
PID_FILE="${LOG_DIR}/${SCRIPT_NAME}_${TIMESTAMP}.pid"

# Function to cleanup on exit
cleanup() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            echo "Process $PID is still running. Log file: $LOG_FILE" >&2
        else
            rm -f "$PID_FILE"
        fi
    fi
}

trap cleanup EXIT

# Run the script in the background
echo "Starting script in background: $SCRIPT_PATH"
echo "Log file: $LOG_FILE"
echo "PID file: $PID_FILE"

# Execute the script in background, redirecting both stdout and stderr to log file
(
    echo "=== Background Script Execution Started ==="
    echo "Script: $SCRIPT_PATH"
    echo "Arguments: ${SCRIPT_ARGS[*]}"
    echo "Started at: $(date)"
    echo "PID: $$"
    echo "============================================"
    echo ""
    
    # Execute the script with all remaining arguments
    exec "$SCRIPT_PATH" "${SCRIPT_ARGS[@]}" 2>&1
    
) > "$LOG_FILE" 2>&1 &

# Get the background process PID
BG_PID=$!

# Save PID to file
echo "$BG_PID" > "$PID_FILE"

# Wait a moment to check if the process started successfully
sleep 0.5
if ! kill -0 "$BG_PID" 2>/dev/null; then
    echo "Error: Background process failed to start. Check log file: $LOG_FILE" >&2
    rm -f "$PID_FILE"
    exit 1
fi

echo "Script is running in background with PID: $BG_PID"
echo "To monitor output: tail -f $LOG_FILE"
echo "To check if still running: kill -0 $BG_PID"
echo "To stop: kill $BG_PID"
echo ""
echo "Log file: $LOG_FILE"
echo "PID file: $PID_FILE"

