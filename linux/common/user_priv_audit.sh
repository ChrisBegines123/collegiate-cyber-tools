#!/bin/sh
# user_priv_audit.sh
# Distro-agnostic (POSIX sh) audit of local accounts and their privileges.
# Optionally diffs the accounts actually on the box against an expected
# user list to flag unauthorized/missing accounts.
#
# Usage: user_priv_audit.sh [-l expected_users_file] [-m min_uid]
#   -l FILE   file with one expected username per line (# comments/blank lines ok)
#   -m UID    minimum UID treated as a human account (default 1000)
#
# Run as root for a complete picture (shadow file, sudoers lookups).

set -eu

EXPECTED_LIST=""
MIN_UID=1000

usage() {
    echo "Usage: $0 [-l expected_users_file] [-m min_uid]" >&2
    exit 1
}

while getopts "l:m:h" opt; do
    case "$opt" in
        l) EXPECTED_LIST="$OPTARG" ;;
        m) MIN_UID="$OPTARG" ;;
        h|*) usage ;;
    esac
done

command -v getent >/dev/null 2>&1 || { echo "getent not found; cannot continue" >&2; exit 1; }

if [ "$(id -u)" -ne 0 ]; then
    echo "NOTE: not running as root; sudoers/shadow checks will be incomplete." >&2
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "=== Local account inventory (UID 0 or UID >= $MIN_UID) ==="
printf '%-16s %-6s %-6s %-30s %-14s %-8s %s\n' "USER" "UID" "GID" "GROUPS" "SHELL" "LOCKED" "SUDO"

getent passwd | awk -F: -v minuid="$MIN_UID" '$3==0 || $3>=minuid' > "$TMPDIR/passwd.lst"

while IFS=: read -r name _pw uid gid _gecos _home shell; do
    groups=$(id -Gn "$name" 2>/dev/null | tr ' ' ',')

    lockstatus="n/a"
    if command -v passwd >/dev/null 2>&1; then
        pstatus=$(passwd -S "$name" 2>/dev/null | awk '{print $2}')
        case "$pstatus" in
            L) lockstatus="LOCKED" ;;
            NP) lockstatus="NO_PASS" ;;
            P) lockstatus="active" ;;
            *) lockstatus="unknown" ;;
        esac
    fi

    sudo_priv="no"
    if [ "$uid" = "0" ]; then
        sudo_priv="root"
    fi
    case ",$groups," in
        *,wheel,*|*,sudo,*|*,admin,*) sudo_priv="yes(group)" ;;
    esac
    if [ "$(id -u)" -eq 0 ] && command -v sudo >/dev/null 2>&1; then
        if sudo -l -U "$name" 2>/dev/null | grep -qv "not allowed"; then
            case "$sudo_priv" in
                no) sudo_priv="yes(sudoers)" ;;
            esac
        fi
    fi

    printf '%-16s %-6s %-6s %-30s %-14s %-8s %s\n' "$name" "$uid" "$gid" "$groups" "$shell" "$lockstatus" "$sudo_priv"

    if [ "$uid" = "0" ] && [ "$name" != "root" ]; then
        echo "  [!] WARNING: non-root account with UID 0: $name"
    fi
done < "$TMPDIR/passwd.lst"

echo
echo "=== Password hash anomalies (/etc/shadow) ==="
if [ -r /etc/shadow ]; then
    awk -F: '$2==""{print "  [!] EMPTY PASSWORD FIELD: "$1; found=1} END{if(!found) print "  none found"}' /etc/shadow
else
    echo "  (cannot read /etc/shadow - re-run as root for full audit)"
fi

if [ -n "$EXPECTED_LIST" ]; then
    [ -r "$EXPECTED_LIST" ] || { echo "Cannot read expected list: $EXPECTED_LIST" >&2; exit 1; }

    echo
    echo "=== Diff against expected user list ($EXPECTED_LIST) ==="
    awk -F: '{print $1}' "$TMPDIR/passwd.lst" | sort -u > "$TMPDIR/actual.lst"
    grep -Ev '^[[:space:]]*(#|$)' "$EXPECTED_LIST" | sort -u > "$TMPDIR/expected.lst"

    echo "-- Present on system but NOT in expected list --"
    comm -23 "$TMPDIR/actual.lst" "$TMPDIR/expected.lst" | sed 's/^/  [!] /'

    echo "-- In expected list but MISSING from system --"
    comm -13 "$TMPDIR/actual.lst" "$TMPDIR/expected.lst" | sed 's/^/  [!] /'
fi
