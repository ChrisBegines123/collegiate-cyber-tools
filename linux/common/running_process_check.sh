#!/bin/bash

#
# Process Scores
#
# Scores currently running processes based on:
#   - Executable location
#   - Parent process
#   - Command line behavior
#   - Privilege level
#   - Network activity
#
# This is intended as a quick triage tool,
# not a malware detector.
# Basic flow
# Enumerate Processes
#        ↓
# Collect Metadata
#        ↓
# Apply Detection Rules
#        ↓
# Assign Score
#        ↓
# Sort By Score
#        ↓
# Print Table
#        ↓
# Print Explanations
#        ↓
# Print Summary
#

SHOW_ZERO_SCORE=true

TMP_DATA=$(mktemp)

cleanup() {
    rm -f "$TMP_DATA"
}
trap cleanup EXIT

#########################################################
# Determine if an IP is internal/private
#########################################################

is_internal_ip() {

    local ip="$1"

    [[ -z "$ip" ]] && return 0

    [[ "$ip" == 127.* ]] && return 0
    [[ "$ip" == 10.* ]] && return 0
    [[ "$ip" == 192.168.* ]] && return 0

    if [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
        return 0
    fi

    [[ "$ip" == "::1" ]] && return 0
    [[ "$ip" == fe80:* ]] && return 0
    [[ "$ip" == fc* ]] && return 0
    [[ "$ip" == fd* ]] && return 0

    return 1
}

#########################################################
# Gather network information for PID
#########################################################

get_network_info() {

    local pid="$1"

    ss -tunpH 2>/dev/null | grep -F "pid=$pid," || true
}

#########################################################
# Analyze one process
#########################################################

analyze_process() {

    local pid="$1"

    [[ -r "/proc/$pid/status" ]] || return

    local score=0
    local reasons=""
    local network_summary=""

    local name
    local ppid
    local uid
    local user
    local exe
    local cmdline
    local parent

    name=$(awk '/^Name:/ {print $2}' "/proc/$pid/status" 2>/dev/null)
    ppid=$(awk '/^PPid:/ {print $2}' "/proc/$pid/status" 2>/dev/null)
    uid=$(awk '/^Uid:/ {print $2}' "/proc/$pid/status" 2>/dev/null)

    user=$(getent passwd "$uid" 2>/dev/null | cut -d: -f1)
    user=${user:-$uid}

    exe=$(readlink "/proc/$pid/exe" 2>/dev/null)
    cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)

    [[ -z "$exe" ]] && exe="unknown"
    [[ -z "$cmdline" ]] && cmdline="[$name]"

    if [[ -f "/proc/$ppid/comm" ]]; then
        parent=$(cat "/proc/$ppid/comm")
    else
        parent="unknown"
    fi

    #####################################################
    # Ignore known WSL helper processes
    #####################################################

    case "$name" in
        Relay*|SessionLeader)
            return
            ;;
    esac

    #####################################################
    # Executable location scoring
    #####################################################

    if [[ "$exe" == /dev/shm/* ]]; then
        ((score+=5))
        reasons+="+5 Executable running from /dev/shm\n"
    fi

    if [[ "$exe" == /tmp/* ]]; then
        ((score+=4))
        reasons+="+4 Executable running from /tmp\n"
    fi

    if [[ "$exe" == /var/tmp/* ]]; then
        ((score+=4))
        reasons+="+4 Executable running from /var/tmp\n"
    fi

    if [[ "$exe" == /root/* ]]; then
        ((score+=2))
        reasons+="+2 Executable located in /root\n"
    fi

    if [[ "$exe" == *"/Downloads/"* ]]; then
        ((score+=2))
        reasons+="+2 Executable running from Downloads\n"
    fi

    if [[ "$exe" == *"(deleted)"* ]]; then
        ((score+=6))
        reasons+="+6 Executable deleted from disk\n"
    fi

    #####################################################
    # Interpreters
    #####################################################

    if [[ "$name" =~ ^(python|python3|perl|php|ruby|lua|node)$ ]]; then
        ((score+=1))
        reasons+="+1 Interpreter process\n"
    fi

    #####################################################
    # Inline execution
    #####################################################

    if [[ "$cmdline" =~ python3?[[:space:]]+-c ]]; then
        ((score+=2))
        reasons+="+2 Inline Python execution\n"
    fi

    if [[ "$cmdline" =~ perl[[:space:]]+-e ]]; then
        ((score+=2))
        reasons+="+2 Inline Perl execution\n"
    fi

    if [[ "$cmdline" =~ php[[:space:]]+-r ]]; then
        ((score+=2))
        reasons+="+2 Inline PHP execution\n"
    fi

    if [[ "$cmdline" =~ bash[[:space:]]+-c ]]; then
        ((score+=2))
        reasons+="+2 Bash command execution\n"
    fi

    #####################################################
    # Download piped to shell
    #####################################################

    if [[ "$cmdline" =~ (curl|wget).*\|.*(bash|sh) ]]; then
        ((score+=8))
        reasons+="+8 Download piped into shell\n"
    fi

    #####################################################
    # Reverse shell indicators
    #####################################################

    if [[ "$cmdline" == *"/dev/tcp/"* ]]; then
        ((score+=10))
        reasons+="+10 Bash TCP redirection\n"
    fi

    if [[ "$cmdline" =~ (nc|ncat|netcat).*(-e|--exec) ]]; then
        ((score+=10))
        reasons+="+10 Netcat execution flag\n"
    fi

    if [[ "$cmdline" == *"socat"* && "$cmdline" == *"exec:"* ]]; then
        ((score+=10))
        reasons+="+10 Socat execution behavior\n"
    fi

    #####################################################
    # Network utilities
    #####################################################

    if [[ "$name" =~ ^(nc|ncat|netcat|socat)$ ]]; then
        ((score+=3))
        reasons+="+3 Network utility execution\n"
    fi

    #####################################################
    # Service spawning shell/interpreter
    #####################################################

    if [[ "$parent" =~ ^(apache2|httpd|nginx|php-fpm|mysqld|postgres)$ ]]; then

        if [[ "$name" =~ ^(bash|sh|dash|zsh|python|python3|perl|php|nc|ncat|netcat|socat)$ ]]; then
            ((score+=6))
            reasons+="+6 Service spawned shell/interpreter\n"
        fi
    fi

    #####################################################
    # Root shell
    #####################################################

    if [[ "$uid" == "0" && "$name" =~ ^(bash|sh|dash|zsh)$ ]]; then
        ((score+=2))
        reasons+="+2 Root shell\n"
    fi

    #####################################################
    # Network analysis
    #####################################################

    local net_lines
    net_lines=$(get_network_info "$pid")

    if [[ -n "$net_lines" ]]; then

        local external_found=0

        while IFS= read -r line; do

            [[ -z "$line" ]] && continue

            network_summary+="$line"$'\n'

            remote=$(awk '{print $5}' <<< "$line")
            remote="${remote%:*}"

            if ! is_internal_ip "$remote"; then
                external_found=1
            fi

        done <<< "$net_lines"

        if ((external_found)); then
            ((score+=4))
            reasons+="+4 External network connection\n"
        else
            ((score+=1))
            reasons+="+1 Internal network connection\n"
        fi
    fi

    #####################################################
    # Save record
    #####################################################

    printf "%d|%s|%s|%s|%s|%s|%s|%s|%s\n" \
        "$score" \
        "$pid" \
        "$user" \
        "$name" \
        "$parent" \
        "$exe" \
        "$(echo "$reasons" | tr '\n' ';')" \
        "$(echo "$network_summary" | tr '\n' ';')" \
        "$cmdline" \
        >> "$TMP_DATA"
}

#########################################################
# Collect process data
#########################################################

echo
echo "PROCESS SCORES"
echo "===================================================================="
echo

for procdir in /proc/[0-9]*; do

    pid="${procdir##*/}"

    [[ "$pid" =~ ^[0-9]+$ ]] || continue

    analyze_process "$pid"

done

#########################################################
# Header
#########################################################

printf "%-6s %-7s %-12s %-18s %-15s %s\n" \
    "SCORE" "PID" "USER" "NAME" "PARENT" "EXECUTABLE"

printf "%-6s %-7s %-12s %-18s %-15s %s\n" \
    "-----" "-------" "------------" "------------------" "---------------" "----------"

#########################################################
# Summary counters
#########################################################

TOTAL=0
NONZERO=0
HIGHEST=0

#########################################################
# Print sorted table
#########################################################

sort -t'|' -k1,1nr "$TMP_DATA" | while IFS='|' read -r score pid user name parent exe reasons network cmdline
do

    ((TOTAL++))

    if ((score > HIGHEST)); then
        HIGHEST=$score
    fi

    if ((score > 0)); then
        ((NONZERO++))
    fi

    if [[ "$SHOW_ZERO_SCORE" == "false" && "$score" -eq 0 ]]; then
        continue
    fi

    printf "%-6s %-7s %-12s %-18s %-15s %s\n" \
        "$score" "$pid" "$user" "$name" "$parent" "$exe"

done

echo
echo "===================================================================="
echo "DETAILS (Processes with Score > 0)"
echo "===================================================================="

echo

sort -t'|' -k1,1nr "$TMP_DATA" | while IFS='|' read -r score pid user name parent exe reasons network cmdline
do

    ((score == 0)) && continue

    echo "--------------------------------------------------------------------"
    echo "PID:        $pid"
    echo "Score:      $score"
    echo "User:       $user"
    echo "Name:       $name"
    echo "Parent:     $parent"
    echo "Executable: $exe"
    echo

    echo "Reasons:"
    echo "$reasons" | tr ';' '\n'

    echo

    if [[ -n "$network" ]]; then
        echo "Connections:"
        echo "$network" | tr ';' '\n'
        echo
    fi
done

echo
echo "===================================================================="
echo "SUMMARY"
echo "===================================================================="

TOTAL=$(wc -l < "$TMP_DATA")

NONZERO=$(awk -F'|' '$1 > 0 {count++} END {print count+0}' "$TMP_DATA")

HIGHEST=$(awk -F'|' '
BEGIN{max=0}
$1 > max {max=$1}
END{print max}
' "$TMP_DATA")

echo "Processes Examined : $TOTAL"
echo "Processes Scored >0: $NONZERO"
echo "Highest Score      : $HIGHEST"
echo "===================================================================="