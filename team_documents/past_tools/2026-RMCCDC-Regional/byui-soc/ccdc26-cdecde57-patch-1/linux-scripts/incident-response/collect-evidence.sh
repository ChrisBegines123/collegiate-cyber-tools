#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Evidence Collection
# Collect forensic evidence during incident

source "$(dirname "$0")/../utils/common.sh"
require_root

header "Evidence Collection"

EVIDENCE_DIR="/tmp/evidence-$(hostname)-$(timestamp)"
mkdir -p "$EVIDENCE_DIR"

#=============================================================================
# COLLECT SYSTEM INFO
#=============================================================================
collect_system_info() {
    header "Collecting System Information"
    
    local dir="$EVIDENCE_DIR/system"
    mkdir -p "$dir"
    
    hostname > "$dir/hostname.txt"
    date > "$dir/date.txt"
    uname -a > "$dir/uname.txt"
    uptime > "$dir/uptime.txt"
    cat /etc/os-release > "$dir/os-release.txt" 2>/dev/null
    
    success "System info collected"
}

#=============================================================================
# COLLECT USER DATA
#=============================================================================
collect_user_data() {
    header "Collecting User Data"
    
    local dir="$EVIDENCE_DIR/users"
    mkdir -p "$dir"
    
    cp /etc/passwd "$dir/"
    cp /etc/shadow "$dir/" 2>/dev/null
    cp /etc/group "$dir/"
    cp /etc/sudoers "$dir/" 2>/dev/null
    cp -r /etc/sudoers.d "$dir/" 2>/dev/null
    
    who -a > "$dir/who.txt"
    last > "$dir/last.txt"
    lastb > "$dir/lastb.txt" 2>/dev/null
    
    # Collect bash histories
    mkdir -p "$dir/histories"
    for home in /home/* /root; do
        local user=$(basename "$home")
        [ "$home" == "/root" ] && user="root"
        
        for histfile in .bash_history .zsh_history .history; do
            if [ -f "$home/$histfile" ]; then
                cp "$home/$histfile" "$dir/histories/${user}_${histfile}"
            fi
        done
    done
    
    # SSH keys
    mkdir -p "$dir/ssh_keys"
    for home in /home/* /root; do
        local user=$(basename "$home")
        [ "$home" == "/root" ] && user="root"
        
        if [ -d "$home/.ssh" ]; then
            cp -r "$home/.ssh" "$dir/ssh_keys/$user"
        fi
    done
    
    success "User data collected"
}

#=============================================================================
# COLLECT PROCESS DATA
#=============================================================================
collect_process_data() {
    header "Collecting Process Data"
    
    local dir="$EVIDENCE_DIR/processes"
    mkdir -p "$dir"
    
    ps auxf > "$dir/ps-auxf.txt"
    ps -eo pid,ppid,user,uid,gid,tty,stat,time,cmd > "$dir/ps-full.txt"
    pstree -p > "$dir/pstree.txt" 2>/dev/null
    
    # /proc info for each process
    mkdir -p "$dir/proc"
    for pid in $(ps -eo pid --no-headers); do
        if [ -d "/proc/$pid" ]; then
            mkdir -p "$dir/proc/$pid"
            cat "/proc/$pid/cmdline" > "$dir/proc/$pid/cmdline" 2>/dev/null
            cat "/proc/$pid/environ" > "$dir/proc/$pid/environ" 2>/dev/null
            ls -la "/proc/$pid/exe" > "$dir/proc/$pid/exe" 2>/dev/null
            ls -la "/proc/$pid/cwd" > "$dir/proc/$pid/cwd" 2>/dev/null
            ls -la "/proc/$pid/fd" > "$dir/proc/$pid/fd-list" 2>/dev/null
        fi
    done
    
    success "Process data collected"
}

#=============================================================================
# COLLECT NETWORK DATA
#=============================================================================
collect_network_data() {
    header "Collecting Network Data"
    
    local dir="$EVIDENCE_DIR/network"
    mkdir -p "$dir"
    
    ss -tunapl > "$dir/ss-tunapl.txt"
    ss -tnp > "$dir/ss-established.txt"
    netstat -an > "$dir/netstat.txt" 2>/dev/null
    
    ip addr > "$dir/ip-addr.txt"
    ip route > "$dir/ip-route.txt"
    ip neigh > "$dir/arp.txt"
    
    iptables -L -n -v > "$dir/iptables.txt"
    iptables-save > "$dir/iptables-save.txt"
    
    cat /etc/hosts > "$dir/hosts.txt"
    cat /etc/resolv.conf > "$dir/resolv.txt"
    
    # DNS cache if available
    if command -v systemd-resolve &>/dev/null; then
        systemd-resolve --statistics > "$dir/dns-stats.txt" 2>/dev/null
    fi
    
    success "Network data collected"
}

#=============================================================================
# COLLECT LOGS
#=============================================================================
collect_logs() {
    header "Collecting Logs"
    
    local dir="$EVIDENCE_DIR/logs"
    mkdir -p "$dir"
    
    # System logs
    local logs=(
        "/var/log/auth.log"
        "/var/log/secure"
        "/var/log/syslog"
        "/var/log/messages"
        "/var/log/kern.log"
        "/var/log/cron"
        "/var/log/audit/audit.log"
        "/var/log/wtmp"
        "/var/log/btmp"
        "/var/log/lastlog"
    )
    
    for log in "${logs[@]}"; do
        if [ -f "$log" ]; then
            cp "$log" "$dir/"
        fi
    done
    
    # Journald
    journalctl --since "24 hours ago" > "$dir/journald-24h.log" 2>/dev/null
    journalctl -u sshd > "$dir/journald-sshd.log" 2>/dev/null
    
    # Apache/nginx logs
    cp /var/log/apache2/*.log "$dir/" 2>/dev/null
    cp /var/log/nginx/*.log "$dir/" 2>/dev/null
    cp /var/log/httpd/*.log "$dir/" 2>/dev/null
    
    success "Logs collected"
}

#=============================================================================
# COLLECT PERSISTENCE ARTIFACTS
#=============================================================================
collect_persistence() {
    header "Collecting Persistence Artifacts"
    
    local dir="$EVIDENCE_DIR/persistence"
    mkdir -p "$dir"
    
    # Cron
    mkdir -p "$dir/cron"
    cp /etc/crontab "$dir/cron/"
    cp -r /etc/cron.d "$dir/cron/" 2>/dev/null
    cp -r /etc/cron.daily "$dir/cron/" 2>/dev/null
    cp -r /etc/cron.hourly "$dir/cron/" 2>/dev/null
    cp -r /var/spool/cron "$dir/cron/" 2>/dev/null
    
    for user in $(cut -d: -f1 /etc/passwd); do
        crontab -l -u "$user" > "$dir/cron/crontab-$user" 2>/dev/null
    done
    
    # Services
    mkdir -p "$dir/services"
    cp -r /etc/systemd/system "$dir/services/" 2>/dev/null
    cp -r /etc/init.d "$dir/services/" 2>/dev/null
    systemctl list-units --type=service > "$dir/services/systemctl-list.txt" 2>/dev/null
    systemctl list-unit-files --type=service > "$dir/services/systemctl-files.txt" 2>/dev/null
    
    # Startup
    mkdir -p "$dir/startup"
    cp /etc/rc.local "$dir/startup/" 2>/dev/null
    cp -r /etc/profile.d "$dir/startup/" 2>/dev/null
    cp /etc/profile "$dir/startup/" 2>/dev/null
    cp /etc/bash.bashrc "$dir/startup/" 2>/dev/null
    
    success "Persistence artifacts collected"
}

#=============================================================================
# COLLECT MODIFIED FILES
#=============================================================================
collect_modified_files() {
    header "Collecting Recently Modified Files"
    
    local dir="$EVIDENCE_DIR/modified"
    mkdir -p "$dir"
    
    # List of modified files
    find /etc -type f -mtime -7 > "$dir/etc-modified-7d.txt" 2>/dev/null
    find /var -type f -mtime -7 > "$dir/var-modified-7d.txt" 2>/dev/null
    find /home -type f -mtime -7 > "$dir/home-modified-7d.txt" 2>/dev/null
    find /root -type f -mtime -7 > "$dir/root-modified-7d.txt" 2>/dev/null
    
    # Files in temp directories
    find /tmp -type f > "$dir/tmp-files.txt" 2>/dev/null
    find /var/tmp -type f > "$dir/var-tmp-files.txt" 2>/dev/null
    find /dev/shm -type f > "$dir/dev-shm-files.txt" 2>/dev/null
    
    # Copy suspicious files
    mkdir -p "$dir/suspicious"
    find /tmp /var/tmp /dev/shm -type f -executable 2>/dev/null | while read -r file; do
        cp "$file" "$dir/suspicious/" 2>/dev/null
    done
    
    success "Modified files collected"
}

#=============================================================================
# HASH CRITICAL FILES
#=============================================================================
hash_critical_files() {
    header "Hashing Critical Files"
    
    local dir="$EVIDENCE_DIR/hashes"
    mkdir -p "$dir"
    
    local critical=(
        "/etc/passwd"
        "/etc/shadow"
        "/etc/group"
        "/etc/sudoers"
        "/etc/ssh/sshd_config"
        "/usr/bin/sudo"
        "/usr/bin/su"
        "/usr/bin/ssh"
        "/usr/sbin/sshd"
        "/bin/bash"
        "/bin/sh"
    )
    
    for file in "${critical[@]}"; do
        if [ -f "$file" ]; then
            sha256sum "$file" >> "$dir/critical-hashes.txt"
        fi
    done
    
    # Hash all binaries in /usr/bin, /usr/sbin
    find /usr/bin /usr/sbin -type f -executable 2>/dev/null | xargs sha256sum > "$dir/binary-hashes.txt" 2>/dev/null
    
    success "File hashes collected"
}

#=============================================================================
# PACKAGE EVIDENCE
#=============================================================================
package_evidence() {
    header "Packaging Evidence"
    
    local tarball="/tmp/evidence-$(hostname)-$(timestamp).tar.gz"
    
    # Create manifest
    find "$EVIDENCE_DIR" -type f > "$EVIDENCE_DIR/MANIFEST.txt"
    
    # Create tarball
    tar -czf "$tarball" -C /tmp "$(basename "$EVIDENCE_DIR")"
    
    # Calculate hash of evidence package
    sha256sum "$tarball" > "${tarball}.sha256"
    
    success "Evidence packaged: $tarball"
    info "SHA256: $(cat "${tarball}.sha256")"
    info "Size: $(du -h "$tarball" | awk '{print $1}')"
}

#=============================================================================
# FULL COLLECTION
#=============================================================================
full_collection() {
    collect_system_info
    collect_user_data
    collect_process_data
    collect_network_data
    collect_logs
    collect_persistence
    collect_modified_files
    hash_critical_files
    package_evidence
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    echo ""
    echo "Evidence output: $EVIDENCE_DIR"
    echo ""
    echo "Evidence Collection Options:"
    echo "1) Collect system info"
    echo "2) Collect user data"
    echo "3) Collect process data"
    echo "4) Collect network data"
    echo "5) Collect logs"
    echo "6) Collect persistence artifacts"
    echo "7) Collect recently modified files"
    echo "8) Hash critical files"
    echo "9) Package evidence"
    echo "10) FULL collection (all)"
    echo ""
    read -p "Select option [1-10]: " choice
    
    case $choice in
        1) collect_system_info ;;
        2) collect_user_data ;;
        3) collect_process_data ;;
        4) collect_network_data ;;
        5) collect_logs ;;
        6) collect_persistence ;;
        7) collect_modified_files ;;
        8) hash_critical_files ;;
        9) package_evidence ;;
        10) full_collection ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
