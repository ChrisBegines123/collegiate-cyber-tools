#!/bin/bash
# CCDC26 Monarch - Incident Response Triage
# Quick system overview: sessions, connections, processes, recent activity
# SELF-CONTAINED -- no external dependencies

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; PURPLE='\033[0;35m'; NC='\033[0m'; BOLD='\033[1m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
phase() { echo -e "\n${BOLD}${PURPLE}[PHASE] $1${NC}\n"; }

if [ "$EUID" -ne 0 ]; then error "Must be run as root"; exit 1; fi

TS=$(date +%Y%m%d_%H%M%S)
TRIAGE_DIR="/tmp/triage-${TS}"
mkdir -p "$TRIAGE_DIR"
OUT="$TRIAGE_DIR/triage.txt"

collect() { echo "=== $1 ===" | tee -a "$OUT"; shift; eval "$@" 2>/dev/null | tee -a "$OUT"; echo "" | tee -a "$OUT"; }

echo -e "\n${BOLD}${GREEN}CCDC26 Incident Triage${NC}\n"
info "Output: $TRIAGE_DIR"

phase "System Info"
collect "HOSTNAME"       "hostname"
collect "DATE"           "date"
collect "UPTIME"         "uptime"
collect "KERNEL"         "uname -a"

phase "Active Sessions"
collect "WHO"            "who -a"
collect "W"              "w"
collect "RECENT LOGINS"  "last -20"

phase "Network"
collect "LISTENING PORTS"         "ss -tulpn"
collect "ESTABLISHED CONNECTIONS" "ss -tnp state established"
collect "ALL CONNECTIONS"         "ss -tunapl"

phase "Processes"
collect "TOP CPU"        "ps aux --sort=-%cpu | head -20"
collect "PROCESS TREE"   "ps auxf | head -60"

phase "Suspicious Processes"
collect "FROM TEMP DIRS" "ps aux | awk '\$11 ~ /^\\/tmp|\\/dev\\/shm|\\/var\\/tmp/'"
collect "DELETED BINS"   "ls -la /proc/*/exe 2>/dev/null | grep deleted"

phase "Recent File Changes"
collect "MODIFIED (24h)"  "find /etc /var/www /home /root -type f -mmin -1440 2>/dev/null | head -50"
collect "TEMP DIR FILES"  "find /tmp /var/tmp /dev/shm -type f 2>/dev/null | head -30"

phase "Cron Jobs"
{
    for user in $(cut -d: -f1 /etc/passwd); do
        ct=$(crontab -l -u "$user" 2>/dev/null)
        [ -n "$ct" ] && echo "--- $user ---" && echo "$ct"
    done
} | tee -a "$OUT"

phase "Auth Logs"
collect "AUTH (last 50)" "{ cat /var/log/auth.log /var/log/secure 2>/dev/null; } | tail -50"
collect "FAILED LOGINS"  "grep -i 'failed\|invalid' /var/log/auth.log /var/log/secure 2>/dev/null | tail -30"

phase "Reverse Shell Indicators"
collect "SUSPICIOUS PORTS" "ss -tnp | grep -E ':(4444|5555|6666|7777|8888|9999|1234|31337) '"
collect "BASH -I PROCS"    "ps aux | grep -E 'bash.*-i|/dev/tcp|/dev/udp|nc.*-e|ncat|netcat' | grep -v grep"

# Package
TARBALL="/tmp/triage-$(hostname)-${TS}.tar.gz"
tar -czf "$TARBALL" -C /tmp "triage-${TS}" 2>/dev/null

echo ""
ok "Triage complete"
info "Report: $OUT"
info "Archive: $TARBALL"
