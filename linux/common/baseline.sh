#!/bin/bash

INTERVAL=1
ALERT_THRESHOLD=3
LOG_FILE="./baseline.log"
ALERT_FILE="./alerts.log"

declare -A previous
declare -A previous_users
declare -A previous_groups

get_process_info() {
    local pid="$1"

    [[ -r "/proc/$pid/status" ]] || return 1

    local name ppid uid user cmdline exe parent_name

    name=$(awk '/^Name:/ {print $2}' "/proc/$pid/status" 2>/dev/null)
    ppid=$(awk '/^PPid:/ {print $2}' "/proc/$pid/status" 2>/dev/null)
    uid=$(awk '/^Uid:/ {print $2}' "/proc/$pid/status" 2>/dev/null)

    user=$(getent passwd "$uid" | cut -d: -f1)
    user=${user:-$uid}

    cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    exe=$(readlink "/proc/$pid/exe" 2>/dev/null)

    if [[ -r "/proc/$ppid/comm" ]]; then
        parent_name=$(cat "/proc/$ppid/comm")
    else
        parent_name="unknown"
    fi

    [[ -n "$cmdline" ]] || cmdline="[$name]"
    [[ -n "$exe" ]] || exe="unknown"

    PROCESS_NAME="$name"
    PROCESS_PPID="$ppid"
    PROCESS_USER="$user"
    PROCESS_UID="$uid"
    PROCESS_CMD="$cmdline"
    PROCESS_EXE="$exe"
    PROCESS_PARENT="$parent_name"
}

check_process() {
    local pid="$1"
    local score=0
    local reasons=()

    get_process_info "$pid" || return

    # Suspicious command-line patterns

    if [[ "$PROCESS_CMD" == *"/dev/tcp/"* ]]; then
        ((score+=5))
        reasons+=("Bash TCP redirection")
    fi

    if [[ "$PROCESS_CMD" =~ (curl|wget).*\|.*(bash|sh) ]]; then
        ((score+=5))
        reasons+=("Download piped into shell")
    fi

    if [[ "$PROCESS_CMD" =~ (nc|ncat|netcat|socat)[[:space:]]+.*(-e|--exec) ]]; then
        ((score+=5))
        reasons+=("Potential reverse shell")
    fi

    if [[ "$PROCESS_CMD" =~ (python|python3)[[:space:]]+-c ]]; then
        ((score+=2))
        reasons+=("Inline Python execution")
    fi

    if [[ "$PROCESS_CMD" =~ (perl[[:space:]]+-e|php[[:space:]]+-r) ]]; then
        ((score+=2))
        reasons+=("Inline interpreter execution")
    fi

    # Suspicious executable locations

    if [[ "$PROCESS_EXE" == /dev/shm/* ]]; then
        ((score+=4))
        reasons+=("Executable running from /dev/shm")
    fi

    if [[ "$PROCESS_EXE" == /tmp/* ]]; then
        if [[ "$PROCESS_EXE" != /tmp/.mount_* ]]; then
            ((score+=3))
            reasons+=("Executable running from /tmp")
        fi
    fi

    if [[ "$PROCESS_EXE" == /var/tmp/* ]]; then
        ((score+=3))
        reasons+=("Executable running from /var/tmp")
    fi

    if [[ "$PROCESS_EXE" == *"(deleted)"* ]]; then
        ((score+=4))
        reasons+=("Executable deleted from disk")
    fi

    # Suspicious parent processes

    if [[ "$PROCESS_PARENT" =~ ^(apache2|httpd|nginx|php-fpm|mysqld|postgres)$ ]]; then
        if [[ "$PROCESS_NAME" =~ ^(bash|sh|dash|zsh|python|python3|perl|nc|ncat|socat)$ ]]; then
            ((score+=5))
            reasons+=("Shell/interpreter spawned by server")
        fi
    fi

    # Privileged processes

    if [[ "$PROCESS_UID" == "0" && "$PROCESS_NAME" =~ ^(bash|sh|dash|zsh)$ ]]; then
        ((score+=2))
        reasons+=("Root shell")
    fi

    # Network utilities

    if [[ "$PROCESS_NAME" =~ ^(nc|ncat|netcat|socat)$ ]]; then
        ((score+=2))
        reasons+=("Network utility execution")
    fi

    # Log all observed processes

    printf '[%s] PID=%s PPID=%s USER=%s NAME=%s EXE=%s CMD=%s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$pid" "$PROCESS_PPID" "$PROCESS_USER" \
        "$PROCESS_NAME" "$PROCESS_EXE" "$PROCESS_CMD" \
        >> "$LOG_FILE"

    # Alert on suspicious processes

    if ((score >= ALERT_THRESHOLD)); then
        local severity="MEDIUM"

        if ((score >= 5)); then
            severity="HIGH"
        fi

        local alert
        alert=$(printf '[%s] [%s] SCORE=%s PID=%s PPID=%s USER=%s\nName: %s\nParent: %s\nExecutable: %s\nCommand: %s\nReasons: %s\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" \
            "$severity" "$score" "$pid" "$PROCESS_PPID" \
            "$PROCESS_USER" "$PROCESS_NAME" "$PROCESS_PARENT" \
            "$PROCESS_EXE" "$PROCESS_CMD" "${reasons[*]}")

        echo
        echo "$alert"
        echo "----------------------------------------"

        {
            echo "$alert"
            echo "----------------------------------------"
        } >> "$ALERT_FILE"
    fi
}

snapshot() {
    local path pid starttime

    for path in /proc/[0-9]*; do
        [[ -d "$path" ]] || continue
        pid=${path##*/}

        [[ -r "$path/stat" ]] || continue

        local stat
        IFS= read -r stat < "$path/stat" || continue

        # Remove PID and comm fields (comm may contain spaces)
        stat=${stat##*) }

        # Field 22 is starttime; field 3 is now the first field
        local -a fields
        read -r -a fields <<< "$stat"
        starttime=${fields[19]}

        [[ -n "$starttime" ]] || continue

        current["$pid"]="$starttime"

        if [[ -z "${previous[$pid]+x}" || "${previous[$pid]}" != "$starttime" ]]; then
            if [[ "$INITIALIZED" == "true" ]]; then
                check_process "$pid"
            fi
        fi
    done
}

alert_new_user() {
    local user="$1" uid="$2" gid="$3"

    local alert
    alert=$(printf '[%s] [HIGH] NEW USER ACCOUNT CREATED\nUsername: %s\nUID: %s\nGID: %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$user" "$uid" "$gid")

    echo
    echo "$alert"
    echo "----------------------------------------"

    {
        echo "$alert"
        echo "----------------------------------------"
    } >> "$ALERT_FILE"
}

alert_new_group() {
    local group="$1" gid="$2" members="$3"

    local alert
    alert=$(printf '[%s] [HIGH] NEW GROUP CREATED\nGroup: %s\nGID: %s\nMembers: %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$group" "$gid" "${members:-none}")

    echo
    echo "$alert"
    echo "----------------------------------------"

    {
        echo "$alert"
        echo "----------------------------------------"
    } >> "$ALERT_FILE"
}

alert_deleted_user() {
    local user="$1" uid="$2" gid="$3"

    local alert
    alert=$(printf '[%s] [HIGH] USER ACCOUNT DELETED\nUsername: %s\nUID: %s\nGID: %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$user" "$uid" "$gid")

    echo
    echo "$alert"
    echo "----------------------------------------"

    {
        echo "$alert"
        echo "----------------------------------------"
    } >> "$ALERT_FILE"
}

alert_deleted_group() {
    local group="$1" gid="$2"

    local alert
    alert=$(printf '[%s] [HIGH] GROUP DELETED\nGroup: %s\nGID: %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$group" "$gid")

    echo
    echo "$alert"
    echo "----------------------------------------"

    {
        echo "$alert"
        echo "----------------------------------------"
    } >> "$ALERT_FILE"
}

check_deleted_users() {
    local name uid gid

    for name in "${!previous_users[@]}"; do
        if [[ -z "${current_users[$name]+x}" ]]; then
            uid="${previous_users[$name]%%:*}"
            gid="${previous_users[$name]##*:}"
            alert_deleted_user "$name" "$uid" "$gid"
        fi
    done
}

check_deleted_groups() {
    local name

    for name in "${!previous_groups[@]}"; do
        if [[ -z "${current_groups[$name]+x}" ]]; then
            alert_deleted_group "$name" "${previous_groups[$name]}"
        fi
    done
}

snapshot_users() {
    local name _pw uid gid _rest

    while IFS=: read -r name _pw uid gid _rest; do
        [[ -n "$name" ]] || continue
        current_users["$name"]="$uid:$gid"

        if [[ -z "${previous_users[$name]+x}" ]]; then
            if [[ "$INITIALIZED" == "true" ]]; then
                alert_new_user "$name" "$uid" "$gid"
            fi
        fi
    done < /etc/passwd
}

snapshot_groups() {
    local name _pw gid members

    while IFS=: read -r name _pw gid members; do
        [[ -n "$name" ]] || continue
        current_groups["$name"]="$gid"

        if [[ -z "${previous_groups[$name]+x}" ]]; then
            if [[ "$INITIALIZED" == "true" ]]; then
                alert_new_group "$name" "$gid" "$members"
            fi
        fi
    done < /etc/group
}

cleanup() {
    echo
    echo "[*] Monitoring stopped."
    exit 0
}

trap cleanup SIGINT SIGTERM

INITIALIZED=false

echo "[*] NCCDC Process/User/Group Monitor"
echo "[*] Poll interval: ${INTERVAL}s"
echo "[*] Alert threshold: $ALERT_THRESHOLD"
echo "[*] Process log: $LOG_FILE"
echo "[*] Alert log: $ALERT_FILE"
echo "[*] Establishing initial baseline..."

declare -A current
declare -A current_users
declare -A current_groups
snapshot
snapshot_users
snapshot_groups

for pid in "${!current[@]}"; do
    previous["$pid"]="${current[$pid]}"
done

for name in "${!current_users[@]}"; do
    previous_users["$name"]="${current_users[$name]}"
done

for name in "${!current_groups[@]}"; do
    previous_groups["$name"]="${current_groups[$name]}"
done

INITIALIZED=true

echo "[+] Baseline established: ${#previous[@]} processes, ${#previous_users[@]} users, ${#previous_groups[@]} groups"
echo "[*] Monitoring for suspicious processes and new/deleted users and groups..."
echo

while true; do
    sleep "$INTERVAL"

    current=()
    snapshot

    current_users=()
    snapshot_users

    current_groups=()
    snapshot_groups

    check_deleted_users
    check_deleted_groups

    previous=()
    for pid in "${!current[@]}"; do
        previous["$pid"]="${current[$pid]}"
    done

    previous_users=()
    for name in "${!current_users[@]}"; do
        previous_users["$name"]="${current_users[$name]}"
    done

    previous_groups=()
    for name in "${!current_groups[@]}"; do
        previous_groups["$name"]="${current_groups[$name]}"
    done
done

