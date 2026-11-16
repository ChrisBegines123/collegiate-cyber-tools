#!/bin/bash

require_root

clear
while true; do
    echo "(Current Interfaces)"
    ip -br add
    echo
    echo "Enter the network interface to secure (e.g., eth0, ens33):"
    read -r INTERFACE
    clear

    if ip link show dev "$INTERFACE" >/dev/null 2>&1; then
        break
    fi

    echo
    echo "[!] Interface '$INTERFACE' was not found. Please enter a valid interface name."
    echo
done
clear

EXCLUDE_ENABLED=false
EXCLUDE_REGEX=""

echo
echo "Identify traffic to filter if needed"
echo
echo "(Listening Ports)"
netstat -tplen 2>/dev/null
echo
echo "(Established Ports)"
netstat -tpen 2>/dev/null
echo
echo "----------------------------------------"
echo

read -r -p "Exclude network traffic by program-name (e.g., sshd, systemd-resolve)? (y/N): " WANT_EXCLUDE
if [[ "$WANT_EXCLUDE" =~ ^[Yy]$ ]]; then
    EXCLUDE_ENABLED=true
    echo
    echo "Enter program-name values to EXCLUDE (type 'stop' when done)."
    names=()

    while true; do
        read -r -p "exclude program-name> " pname
        pname="${pname//$'\r'/}"
        [[ "$pname" == "stop" ]] && break
        [[ -n "$pname" ]] && names+=("$pname")
    done

    if ((${#names[@]} > 0)); then
        joined="$(printf "%s|" "${names[@]}")"
        joined="${joined%|}"
        EXCLUDE_REGEX="/(${joined})([[:space:]]|$)"
        echo
        echo "[+] Netstat exclusion enabled for: ${names[*]}"
        echo
    else
        EXCLUDE_ENABLED=false
        echo
        echo "[!] No program-names entered; exclusion disabled."
        echo
    fi
fi

print_netstat_excluding() {
    local cmd="$1"
    local title="$2"
    local out

    echo "($title)"
    out="$(eval "$cmd" 2>/dev/null)"

    echo "$out" | head -2

    if [ "$EXCLUDE_ENABLED" = true ] && [ -n "$EXCLUDE_REGEX" ]; then
        echo "$out" | tail -n +3 | grep -E -v "$EXCLUDE_REGEX"
    else
        echo "$out" | tail -n +3
    fi

    echo
}

PARENT_PID=$$
REPORT_FILE="/tmp/incident_report.$$"

trap '
    clear
    if [[ -f "$REPORT_FILE" ]]; then
        less "$REPORT_FILE"
        cat "$REPORT_FILE"
        echo
        echo
        echo Find the report here : $REPORT_FILE
        echo Run the following to turn your interface back on : sudo ip link set $INTERFACE up
    else
        echo "[!] Incident signaled, but report file was not found."
        echo

        NEW_SESSION="$(last | head -n 1)"

        echo "[+] Username Targeted: $(awk "{print \$1}" <<< "$NEW_SESSION")"
        echo "[+] IP of Potential Attacker: $(awk "{print \$3}" <<< "$NEW_SESSION")"
        echo
        echo "(Interfaces after shutdown)"
	ip -br add
	echo
	echo Run the following to turn your interface back on : sudo ip link set $INTERFACE up
	echo
        cat << EoF
The following commands may be useful in identifying more information.

(Get IP / Username Targeted)
last | head -n 5


(Search for the IP)
# View the system / security logs directly, ex last 10 entries. The IP Address can often be found here.
journalctl -n 10
tail -n 10 /var/log/secure

less /var/log/syslog
journalctl -p err -b
less /var/log/auth.log

# System Logs (Example service: cockpit)
journalctl -u SERVICENAME| less
	
# Monitoring the state of a service / basic details:
systemctl status SERVICENAME| less
EoF
    fi
    exit
' TERM

BASELINE="$(last | head -5 | sort)"

monitor_sessions_fast() {
    while true; do
        CURRENT="$(last | head -5 | sort)"
        NEW_SESSION="$(comm -13 <(echo "$BASELINE") <(echo "$CURRENT"))"

        if [ -n "$NEW_SESSION" ]; then
            NS_TPEN="$(netstat -tpen 2>/dev/null)"
            NS_TPLEN="$(netstat -tplen 2>/dev/null)"
            
            sudo ip link set $INTERFACE down

            {
                echo "[!] NEW SESSION DETECTED!"
                echo "[+] >>>  $NEW_SESSION"
                echo
                echo "[+] Username: $(echo $NEW_SESSION | awk '{print $1}')"
                echo "[+] IP: $(echo $NEW_SESSION | awk '{print $3}')"
                echo
                echo "[+] Searching for established / Listening IP addresses - May help identify the attacker"
                echo

                echo "(Listening Ports)"
                echo "$NS_TPLEN"
                echo

                echo "(Established Ports)"
                echo "$NS_TPEN"
                echo

                echo
                echo "(Interfaces after shutdown)"
                ip -br add
                echo
                echo "[+] Time to follow through with your incidence response plan. Don't forget to continue monitoring after you bring the interface back up."
            } > "${REPORT_FILE}.tmp" # We name it as a tmp file until we're ready
            mv "${REPORT_FILE}.tmp" "$REPORT_FILE" # Once we finish writing we publish the report as ready. This ensures the application doesn't read it during writeing.

            kill -TERM "$PARENT_PID"
            exit 0
        fi
    done
}

monitor_sessions_fast &

echo
echo "Monitoring for new sessions on interface: $INTERFACE"
echo "Press Ctrl+C to stop monitoring"
echo "----------------------------------------"

while true; do
    CURRENT="$(last | head -5 | sort)"

    clear
    echo "(User Sessions)"
    echo "$CURRENT"
    echo

    print_netstat_excluding "netstat -tplen" "Listening Ports"
    print_netstat_excluding "netstat -tpen" "Established Ports"

    sleep 3
done
