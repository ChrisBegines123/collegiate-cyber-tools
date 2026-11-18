#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Binary Audit
# Find SUID/SGID binaries, capabilities, and suspicious executables

source "$(dirname "$0")/../utils/common.sh"
require_root

header "Binary and Capability Audit"

#=============================================================================
# KNOWN LEGITIMATE SUID BINARIES
#=============================================================================
LEGITIMATE_SUID=(
    "/usr/bin/sudo"
    "/usr/bin/su"
    "/usr/bin/passwd"
    "/usr/bin/chsh"
    "/usr/bin/chfn"
    "/usr/bin/newgrp"
    "/usr/bin/gpasswd"
    "/usr/bin/mount"
    "/usr/bin/umount"
    "/usr/bin/ping"
    "/usr/bin/ping6"
    "/usr/bin/crontab"
    "/usr/bin/at"
    "/usr/bin/pkexec"
    "/usr/sbin/unix_chkpwd"
    "/usr/lib/openssh/ssh-keysign"
    "/usr/lib/dbus-1.0/dbus-daemon-launch-helper"
    "/usr/lib/policykit-1/polkit-agent-helper-1"
    "/usr/libexec/polkit-agent-helper-1"
    "/usr/lib/snapd/snap-confine"
    "/bin/su"
    "/bin/mount"
    "/bin/umount"
    "/bin/ping"
    "/bin/ping6"
)

#=============================================================================
# FIND SUID BINARIES
#=============================================================================
audit_suid() {
    header "Auditing SUID Binaries"
    
    info "Scanning for SUID binaries..."
    find / -xdev -type f -perm -4000 2>/dev/null | sort | while read -r binary; do
        local is_legitimate=false
        
        for legit in "${LEGITIMATE_SUID[@]}"; do
            if [ "$binary" == "$legit" ]; then
                is_legitimate=true
                break
            fi
        done
        
        if $is_legitimate; then
            success "[KNOWN] $binary"
        else
            log_finding "SUID binary: $binary"
            ls -la "$binary"
            file "$binary"
            
            # Check if it's from a package
            case "$PKG_MGR" in
                apt)
                    local pkg=$(dpkg -S "$binary" 2>/dev/null)
                    [ -n "$pkg" ] && echo "  Package: $pkg"
                    ;;
                dnf|yum)
                    local pkg=$(rpm -qf "$binary" 2>/dev/null)
                    [ -n "$pkg" ] && echo "  Package: $pkg"
                    ;;
            esac
        fi
    done
}

#=============================================================================
# FIND SGID BINARIES
#=============================================================================
audit_sgid() {
    header "Auditing SGID Binaries"
    
    info "Scanning for SGID binaries..."
    find / -xdev -type f -perm -2000 2>/dev/null | sort | while read -r binary; do
        warn "SGID binary: $binary"
        ls -la "$binary"
    done
}

#=============================================================================
# SUID/SGID IN UNUSUAL LOCATIONS
#=============================================================================
audit_suid_unusual() {
    header "SUID/SGID in Unusual Locations"
    
    local unusual_dirs=(
        "/tmp"
        "/var/tmp"
        "/dev/shm"
        "/home"
        "/opt"
        "/var/www"
        "/srv"
    )
    
    for dir in "${unusual_dirs[@]}"; do
        [ -d "$dir" ] || continue
        find "$dir" -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | while read -r binary; do
            log_finding "SUID/SGID in unusual location: $binary"
            ls -la "$binary"
            file "$binary"
        done
    done
}

#=============================================================================
# AUDIT FILE CAPABILITIES
#=============================================================================
audit_capabilities() {
    header "Auditing File Capabilities"
    
    if ! command -v getcap &>/dev/null; then
        warn "getcap not available, installing..."
        pkg_install libcap2-bin 2>/dev/null || pkg_install libcap 2>/dev/null
    fi
    
    if ! command -v getcap &>/dev/null; then
        error "Cannot install getcap"
        return
    fi
    
    info "Files with capabilities:"
    getcap -r / 2>/dev/null | while read -r line; do
        local file=$(echo "$line" | awk '{print $1}')
        local caps=$(echo "$line" | cut -d'=' -f2)
        
        # Dangerous capabilities
        local dangerous_caps=(
            "cap_sys_admin"
            "cap_setuid"
            "cap_setgid"
            "cap_sys_ptrace"
            "cap_sys_module"
            "cap_dac_override"
            "cap_dac_read_search"
            "cap_chown"
            "cap_fowner"
            "cap_net_admin"
            "cap_net_raw"
        )
        
        local is_dangerous=false
        for cap in "${dangerous_caps[@]}"; do
            if echo "$caps" | grep -qi "$cap"; then
                is_dangerous=true
                break
            fi
        done
        
        if $is_dangerous; then
            log_finding "Dangerous capability: $line"
        else
            echo "  $line"
        fi
    done
    
    # Check unusual locations
    info "Capabilities in unusual locations:"
    for dir in /tmp /var/tmp /dev/shm /home; do
        [ -d "$dir" ] || continue
        find "$dir" -type f 2>/dev/null | while read -r file; do
            local cap=$(getcap "$file" 2>/dev/null)
            if [ -n "$cap" ]; then
                log_finding "Capability in unusual location: $cap"
            fi
        done
    done
}

#=============================================================================
# CHECK BINARY INTEGRITY
#=============================================================================
check_binary_integrity() {
    header "Checking Binary Integrity"
    
    local critical_binaries=(
        "/usr/bin/sudo"
        "/usr/bin/su"
        "/usr/bin/passwd"
        "/usr/bin/ssh"
        "/usr/sbin/sshd"
        "/bin/bash"
        "/bin/sh"
        "/usr/bin/login"
        "/usr/bin/crontab"
    )
    
    for binary in "${critical_binaries[@]}"; do
        [ -f "$binary" ] || continue
        
        info "Checking $binary..."
        
        # Check if it's a symlink
        if [ -L "$binary" ]; then
            local target=$(readlink -f "$binary")
            warn "  Symlink to: $target"
        fi
        
        # Get hash
        local hash=$(hash_file "$binary")
        echo "  SHA256: $hash"
        
        # Check package ownership
        case "$PKG_MGR" in
            apt)
                local pkg=$(dpkg -S "$binary" 2>/dev/null)
                if [ -n "$pkg" ]; then
                    echo "  Package: $pkg"
                    # Verify integrity
                    local pkg_name=$(echo "$pkg" | cut -d: -f1)
                    if dpkg --verify "$pkg_name" 2>/dev/null | grep -q "$binary"; then
                        log_finding "Binary modified from package: $binary"
                    fi
                else
                    log_finding "Binary not owned by any package: $binary"
                fi
                ;;
            dnf|yum)
                local pkg=$(rpm -qf "$binary" 2>/dev/null)
                if [ -n "$pkg" ]; then
                    echo "  Package: $pkg"
                    if rpm -V "$pkg" 2>/dev/null | grep -q "$binary"; then
                        log_finding "Binary modified from package: $binary"
                    fi
                else
                    log_finding "Binary not owned by any package: $binary"
                fi
                ;;
        esac
        
        # Check modification time
        local mtime=$(stat -c %Y "$binary")
        local seven_days_ago=$(date -d '7 days ago' +%s)
        if [ "$mtime" -gt "$seven_days_ago" ]; then
            log_finding "Recently modified: $binary"
        fi
    done
}

#=============================================================================
# FIND SUSPICIOUS EXECUTABLES
#=============================================================================
find_suspicious_executables() {
    header "Finding Suspicious Executables"
    
    # Executables in /tmp, /var/tmp, /dev/shm
    info "Executables in temporary directories..."
    for dir in /tmp /var/tmp /dev/shm; do
        [ -d "$dir" ] || continue
        find "$dir" -type f -executable 2>/dev/null | while read -r file; do
            log_finding "Executable in $dir: $file"
            ls -la "$file"
            file "$file"
        done
    done
    
    # Hidden executables
    info "Hidden executables..."
    find /tmp /var/tmp /dev/shm /home /opt -name ".*" -type f -executable 2>/dev/null | while read -r file; do
        log_finding "Hidden executable: $file"
        ls -la "$file"
    done
    
    # Executables with suspicious names
    info "Executables with suspicious names..."
    local suspicious_names=(
        "*shell*"
        "*backdoor*"
        "*reverse*"
        "*bind*"
        "*payload*"
        "*meterpreter*"
        "*beacon*"
        "*implant*"
        "*rootkit*"
        "*keylog*"
        "*dump*"
        "*mimikatz*"
        "*.elf"
    )
    
    for pattern in "${suspicious_names[@]}"; do
        find / -name "$pattern" -type f 2>/dev/null | head -20 | while read -r file; do
            log_finding "Suspicious name: $file"
        done
    done
    
    # Recently created executables
    info "Executables created in last 7 days..."
    find /usr/bin /usr/sbin /usr/local/bin /opt -type f -executable -mtime -7 2>/dev/null | while read -r file; do
        warn "Recent executable: $file ($(stat -c %y "$file" 2>/dev/null))"
    done
}

#=============================================================================
# CHECK FOR PRELOAD HIJACKING
#=============================================================================
check_preload() {
    header "Checking for Library Preloading"
    
    # LD_PRELOAD in environment
    info "Checking LD_PRELOAD..."
    if [ -n "$LD_PRELOAD" ]; then
        log_finding "LD_PRELOAD is set: $LD_PRELOAD"
    fi
    
    # /etc/ld.so.preload
    if [ -f /etc/ld.so.preload ]; then
        log_finding "/etc/ld.so.preload exists:"
        cat /etc/ld.so.preload
    fi
    
    # Check ld.so.conf.d for unusual entries
    info "Checking ld.so.conf.d..."
    for conf in /etc/ld.so.conf.d/*; do
        [ -f "$conf" ] || continue
        while read -r path; do
            [ -z "$path" ] && continue
            [[ "$path" == \#* ]] && continue
            
            # Check for unusual paths
            if [[ "$path" == /tmp/* ]] || [[ "$path" == /home/* ]] || [[ "$path" == /var/tmp/* ]]; then
                log_finding "Suspicious library path in $conf: $path"
            fi
        done < "$conf"
    done
    
    # Check for recently modified libraries
    info "Recently modified libraries..."
    find /lib /lib64 /usr/lib /usr/lib64 -name "*.so*" -mtime -7 2>/dev/null | while read -r lib; do
        warn "Recent library: $lib"
    done
}

#=============================================================================
# REMOVE SUID/SGID
#=============================================================================
remove_suid() {
    header "Remove SUID/SGID from Binary"
    
    read -p "Enter path to binary: " binary_path
    
    if [ ! -f "$binary_path" ]; then
        error "File not found: $binary_path"
        return
    fi
    
    ls -la "$binary_path"
    
    read -p "Remove SUID/SGID? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        chmod u-s,g-s "$binary_path"
        success "Removed SUID/SGID from: $binary_path"
        log_action "Removed SUID/SGID from: $binary_path"
        ls -la "$binary_path"
    fi
}

#=============================================================================
# MAIN MENU
#=============================================================================
main() {
    echo ""
    echo "Binary Audit Options:"
    echo "1) Audit SUID binaries"
    echo "2) Audit SGID binaries"
    echo "3) SUID/SGID in unusual locations"
    echo "4) Audit file capabilities"
    echo "5) Check binary integrity"
    echo "6) Find suspicious executables"
    echo "7) Check library preloading"
    echo "8) Remove SUID/SGID from binary"
    echo "9) Run ALL audits"
    echo ""
    read -p "Select option [1-9]: " choice
    
    case $choice in
        1) audit_suid ;;
        2) audit_sgid ;;
        3) audit_suid_unusual ;;
        4) audit_capabilities ;;
        5) check_binary_integrity ;;
        6) find_suspicious_executables ;;
        7) check_preload ;;
        8) remove_suid ;;
        9)
            audit_suid
            audit_sgid
            audit_suid_unusual
            audit_capabilities
            check_binary_integrity
            find_suspicious_executables
            check_preload
            ;;
        *) error "Invalid option" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
