#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Deploy Monitoring
# Start all monitoring in background

source "$(dirname "$0")/../utils/common.sh"
require_root

SCRIPT_DIR="$(dirname "$0")"

header "Deploy Monitoring"

echo "This will start monitoring scripts in the background."
echo ""
echo "Monitoring options:"
echo "1) Create file integrity baseline"
echo "2) Start file monitoring (continuous)"
echo "3) Start process monitoring"
echo "4) Start network monitoring"
echo "5) Start log watching"
echo "6) Start ALL monitoring"
echo ""
read -p "Select option [1-6]: " choice

case $choice in
    1)
        bash "$SCRIPT_DIR/file-monitor.sh" <<< "1"
        ;;
    2)
        info "Starting file monitor in background..."
        nohup bash "$SCRIPT_DIR/file-monitor.sh" <<< "3" > /var/log/ccdc-toolkit/file-monitor.log 2>&1 &
        echo $! > /var/run/ccdc-file-monitor.pid
        success "File monitor started (PID: $(cat /var/run/ccdc-file-monitor.pid))"
        ;;
    3)
        info "Starting process monitor in background..."
        nohup bash "$SCRIPT_DIR/process-monitor.sh" <<< "3" > /var/log/ccdc-toolkit/process-monitor.log 2>&1 &
        echo $! > /var/run/ccdc-process-monitor.pid
        success "Process monitor started (PID: $(cat /var/run/ccdc-process-monitor.pid))"
        ;;
    4)
        info "Starting network monitor in background..."
        nohup bash "$SCRIPT_DIR/network-monitor.sh" <<< "4" > /var/log/ccdc-toolkit/network-monitor.log 2>&1 &
        echo $! > /var/run/ccdc-network-monitor.pid
        success "Network monitor started (PID: $(cat /var/run/ccdc-network-monitor.pid))"
        ;;
    5)
        info "Starting log watcher in background..."
        nohup bash "$SCRIPT_DIR/log-watcher.sh" <<< "4" > /var/log/ccdc-toolkit/log-watcher.log 2>&1 &
        echo $! > /var/run/ccdc-log-watcher.pid
        success "Log watcher started (PID: $(cat /var/run/ccdc-log-watcher.pid))"
        ;;
    6)
        header "Starting ALL Monitoring"
        
        # Create baseline first
        bash "$SCRIPT_DIR/file-monitor.sh" <<< "1"
        
        # Start all monitors
        nohup bash "$SCRIPT_DIR/file-monitor.sh" <<< "4" > /var/log/ccdc-toolkit/file-monitor.log 2>&1 &
        echo $! > /var/run/ccdc-file-monitor.pid
        
        nohup bash "$SCRIPT_DIR/process-monitor.sh" <<< "3" > /var/log/ccdc-toolkit/process-monitor.log 2>&1 &
        echo $! > /var/run/ccdc-process-monitor.pid
        
        nohup bash "$SCRIPT_DIR/network-monitor.sh" <<< "4" > /var/log/ccdc-toolkit/network-monitor.log 2>&1 &
        echo $! > /var/run/ccdc-network-monitor.pid
        
        success "All monitoring started"
        ;;
    *)
        error "Invalid option"
        exit 1
        ;;
esac

echo ""
info "Monitor logs in /var/log/ccdc-toolkit/"
info "To stop monitors: kill \$(cat /var/run/ccdc-*.pid)"

log_action "Deployed monitoring"
