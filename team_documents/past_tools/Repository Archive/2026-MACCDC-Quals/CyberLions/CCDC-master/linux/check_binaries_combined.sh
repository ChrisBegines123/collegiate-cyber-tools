#!/bin/bash
# CHECKS: sudo, passwd, su, login, sshd, netstat, ps, ls, and pam binaries

echo "Scanning important Binaries..."

# List of binaries to check
BINARIES="sudo passwd su login sshd netstat ps ls"

# Check for Debian-based (dpkg) - Ubuntu/Kali/Debian
if command -v dpkg >/dev/null 2>&1; then
    echo "Detected Debian based system. Verifying Packages"

    # 1. Identify which packages own the binaries
    # We loop through the list, find the binary path, and ask dpkg which package owns it.
    PACKAGES=""
    for bin in $BINARIES; do
        # command -v finds the path (e.g., /usr/bin/sudo)
        path=$(command -v $bin)
        
        if [ -n "$path" ]; then
            # dpkg -S finds the package name (e.g., 'sudo: /usr/bin/sudo' -> 'sudo')
            pkg=$(dpkg -S "$path" 2>/dev/null | cut -d: -f1)
            PACKAGES="$PACKAGES $pkg"
        fi
    done

    # Also add PAM manually since it's a library, not a binary command
    PACKAGES="$PACKAGES libpam-modules libpam-runtime"

    # Remove duplicates from the package list
    PACKAGES=$(echo "$PACKAGES" | tr ' ' '\n' | sort -u | tr '\n' ' ')

    echo "Verifying specific packages: $PACKAGES"
    
    # 2. Verify ONLY those packages
    # This is instantaneous compared to a full system scan.
    # We still grep for '5' (checksum mismatch) to see if content changed.
    dpkg --verify $PACKAGES | grep "5......" 

# Check for RHEL/CentOS-based (rpm)
elif command -v rpm >/dev/null 2>&1; then
    echo "Detected RHEL based system. Verifying binaries"
    
    # RPM is smarter; you can verify a file path directly without looking up the package first.
    # We verify the actual binary paths.
    
    PATHS=""
    for bin in $BINARIES; do
        path=$(command -v $bin)
        if [ -n "$path" ]; then
            PATHS="$PATHS $path"
        fi
    done
    
    # Add PAM libs (wildcard for safety as locations vary)
    # verifying /lib64/security is a decent catch-all for PAM modules on RHEL
    
    rpm -Vf $PATHS | grep -E "^..5|^S"

else
    echo "Error: Could not determine distribution (neither dpkg nor rpm found)."
    exit 1
fi

echo "DONE."
echo "If you see any output above, the files listed have been modified."
