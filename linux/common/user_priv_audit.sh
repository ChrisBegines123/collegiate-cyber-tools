#!/bin/sh
# user_priv_audit.sh
# Distro-agnostic (POSIX sh) audit of local accounts and their privileges.
# Optionally diffs the accounts actually on the box against an expected
# user list to flag unauthorized/missing accounts, and an expected
# privileges list to flag unauthorized group membership.
#
# Usage: user_priv_audit.sh [-l expected_users_file] [-p expected_privs_file]
#                            [-m min_uid] [-o logfile] [-a]
#   -l FILE   file with one expected username per line (# comments/blank lines ok)
#   -p FILE   file of "username:comma,separated,allowed,privileged,groups"
#             (subset of wheel/sudo/admin). Only usernames listed here are
#             checked; anyone in a privileged group they're not authorized
#             for has that group membership removed.
#   -m UID    minimum UID treated as a human account (default 1000)
#   -o FILE   logfile for actions taken (default /var/log/user_priv_audit.log)
#   -a        actually apply remediation (lock/expire/kill sessions for
#             UID-0 clones, empty-password accounts, and accounts not in
#             the expected user list; strip unauthorized group membership
#             for accounts in the expected privileges list). Without -a,
#             every remediation is reported as [DRY-RUN] only.
#
# Run as root for a complete picture (shadow file, sudoers lookups) and to
# actually apply remediation.
#
# Safety: this script will never lock/expire root, and will never touch
# the account it is itself running as (via $SUDO_USER/$LOGNAME/$USER).

set -eu

EXPECTED_LIST=""
EXPECTED_PRIV_FILE=""
MIN_UID=1000
LOGFILE="/var/log/user_priv_audit.log"
APPLY=0

usage() {
    echo "Usage: $0 [-l expected_users_file] [-p expected_privs_file] [-m min_uid] [-o logfile] [-a]" >&2
    exit 1
}

while getopts "l:p:m:o:ah" opt; do
    case "$opt" in
        l) EXPECTED_LIST="$OPTARG" ;;
        p) EXPECTED_PRIV_FILE="$OPTARG" ;;
        m) MIN_UID="$OPTARG" ;;
        o) LOGFILE="$OPTARG" ;;
        a) APPLY=1 ;;
        h|*) usage ;;
    esac
done

command -v getent >/dev/null 2>&1 || { echo "getent not found; cannot continue" >&2; exit 1; }

if [ "$(id -u)" -ne 0 ]; then
    echo "NOTE: not running as root; sudoers/shadow checks will be incomplete." >&2
fi

SELF_USER=${SUDO_USER:-${LOGNAME:-${USER:-}}}
HOSTNAME_STR=$(hostname 2>/dev/null || uname -n 2>/dev/null || echo unknown)

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

log_action() {
    acct=$1
    action=$2
    result=$3
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    line="$ts host=$HOSTNAME_STR user_priv_audit account=$acct action=\"$action\" result=$result"
    { [ -n "$LOGFILE" ] && printf '%s\n' "$line" >> "$LOGFILE"; } 2>/dev/null || true
    { command -v logger >/dev/null 2>&1 && logger -t user_priv_audit "account=$acct action=\"$action\" result=$result"; } 2>/dev/null || true
}

lockdown_account() {
    target=$1
    reason=$2

    if [ "$target" = "root" ]; then
        echo "  [!] REFUSING to lock root account (trigger: $reason)"
        log_action "$target" "lock+expire+kill sessions ($reason)" "skipped-root-protected"
        return
    fi
    if [ -n "$SELF_USER" ] && [ "$target" = "$SELF_USER" ]; then
        echo "  [!] REFUSING to lock the account running this audit ($target, trigger: $reason)"
        log_action "$target" "lock+expire+kill sessions ($reason)" "skipped-self-protected"
        return
    fi

    if [ "$APPLY" -ne 1 ]; then
        echo "  [DRY-RUN] would lock+expire+kill sessions for $target ($reason)"
        log_action "$target" "lock+expire+kill sessions ($reason)" "dry-run"
        return
    fi

    if [ "$(id -u)" -ne 0 ]; then
        echo "  [!] Cannot remediate $target ($reason): not running as root"
        log_action "$target" "lock+expire+kill sessions ($reason)" "skipped-not-root"
        return
    fi

    step_ok=1
    passwd -l "$target" >/dev/null 2>&1 || step_ok=0
    usermod -e 1 "$target" >/dev/null 2>&1 || step_ok=0
    pkill -KILL -u "$target" >/dev/null 2>&1 || true

    if [ "$step_ok" -eq 1 ]; then
        echo "  [ACTION] locked, expired, and killed sessions for $target ($reason)"
        log_action "$target" "lock+expire+kill sessions ($reason)" "success"
    else
        echo "  [ACTION] partial failure locking/expiring $target ($reason) - check manually"
        log_action "$target" "lock+expire+kill sessions ($reason)" "partial-failure"
    fi
}

remediate_privilege() {
    target=$1
    group=$2

    if [ -n "$SELF_USER" ] && [ "$target" = "$SELF_USER" ]; then
        echo "  [!] REFUSING to modify groups for the account running this audit ($target)"
        log_action "$target" "remove from unauthorized group '$group'" "skipped-self-protected"
        return
    fi

    if [ "$APPLY" -ne 1 ]; then
        echo "  [DRY-RUN] would remove $target from unauthorized group '$group'"
        log_action "$target" "remove from unauthorized group '$group'" "dry-run"
        return
    fi

    if [ "$(id -u)" -ne 0 ]; then
        echo "  [!] Cannot remediate $target: not running as root"
        log_action "$target" "remove from unauthorized group '$group'" "skipped-not-root"
        return
    fi

    if gpasswd -d "$target" "$group" >/dev/null 2>&1; then
        echo "  [ACTION] removed $target from unauthorized group '$group'"
        log_action "$target" "remove from unauthorized group '$group'" "success"
    else
        echo "  [ACTION] FAILED to remove $target from group '$group' - check manually"
        log_action "$target" "remove from unauthorized group '$group'" "failure"
    fi
}

if [ -n "$EXPECTED_PRIV_FILE" ]; then
    [ -r "$EXPECTED_PRIV_FILE" ] || { echo "Cannot read expected privileges file: $EXPECTED_PRIV_FILE" >&2; exit 1; }
    grep -Ev '^[[:space:]]*(#|$)' "$EXPECTED_PRIV_FILE" > "$TMPDIR/priv.lst"
else
    : > "$TMPDIR/priv.lst"
fi

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
        lockdown_account "$name" "non-root account with UID 0"
    fi

    if [ -s "$TMPDIR/priv.lst" ] && grep -q "^$name:" "$TMPDIR/priv.lst"; then
        allowed=$(awk -F: -v n="$name" '$1==n{print $2}' "$TMPDIR/priv.lst")
        for g in wheel sudo admin; do
            case ",$groups," in
                *",$g,"*)
                    case ",$allowed," in
                        *",$g,"*) : ;;
                        *)
                            echo "  [!] UNAUTHORIZED PRIVILEGE: $name is in '$g' but not authorized for it"
                            remediate_privilege "$name" "$g"
                            ;;
                    esac
                    ;;
            esac
        done
    fi
done < "$TMPDIR/passwd.lst"

echo
echo "=== Password hash anomalies (/etc/shadow) ==="
: > "$TMPDIR/emptypw.lst"
if [ -r /etc/shadow ]; then
    awk -F: -v tmpfile="$TMPDIR/emptypw.lst" '$2==""{print "  [!] EMPTY PASSWORD FIELD: "$1; print $1 > tmpfile; found=1} END{if(!found) print "  none found"}' /etc/shadow
else
    echo "  (cannot read /etc/shadow - re-run as root for full audit)"
fi

if [ -s "$TMPDIR/emptypw.lst" ]; then
    while IFS= read -r pwname; do
        if awk -F: -v n="$pwname" '$1==n{found=1} END{exit !found}' "$TMPDIR/passwd.lst"; then
            lockdown_account "$pwname" "empty password field in /etc/shadow"
        fi
    done < "$TMPDIR/emptypw.lst"
fi

if [ -n "$EXPECTED_LIST" ]; then
    [ -r "$EXPECTED_LIST" ] || { echo "Cannot read expected list: $EXPECTED_LIST" >&2; exit 1; }

    echo
    echo "=== Diff against expected user list ($EXPECTED_LIST) ==="
    awk -F: '{print $1}' "$TMPDIR/passwd.lst" | sort -u > "$TMPDIR/actual.lst"
    grep -Ev '^[[:space:]]*(#|$)' "$EXPECTED_LIST" | sort -u > "$TMPDIR/expected.lst"

    echo "-- Present on system but NOT in expected list --"
    comm -23 "$TMPDIR/actual.lst" "$TMPDIR/expected.lst" > "$TMPDIR/unexpected.lst"
    sed 's/^/  [!] /' "$TMPDIR/unexpected.lst"

    echo "-- In expected list but MISSING from system --"
    comm -13 "$TMPDIR/actual.lst" "$TMPDIR/expected.lst" | sed 's/^/  [!] /'

    if [ -s "$TMPDIR/unexpected.lst" ]; then
        while IFS= read -r extraname; do
            lockdown_account "$extraname" "account not in expected user list"
        done < "$TMPDIR/unexpected.lst"
    fi
fi
