#!/bin/bash
# CCDC26 Monarch - PII/Compliance Scanner
# Scan common directories for SSNs, credit cards, emails, phone numbers
# SELF-CONTAINED -- no external dependencies

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
finding() { echo -e "${RED}[FINDING]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then
    error "Must be run as root"
    exit 1
fi

echo -e "\n${BOLD}[PHASE] PII/Compliance Scan${NC}\n"

SCAN_DIRS="/home /var/www /srv /opt /tmp"
FILE_TYPES="-name '*.txt' -o -name '*.csv' -o -name '*.doc' -o -name '*.docx' -o -name '*.xls' -o -name '*.xlsx' -o -name '*.pdf' -o -name '*.sql' -o -name '*.log' -o -name '*.conf' -o -name '*.html' -o -name '*.php' -o -name '*.py' -o -name '*.json' -o -name '*.xml' -o -name '*.yml' -o -name '*.yaml' -o -name '*.md' -o -name '*.bak'"
TOTAL_FINDINGS=0

scan_pattern() {
    local label="$1"
    local pattern="$2"
    local count=0

    for dir in $SCAN_DIRS; do
        [ -d "$dir" ] || continue
        while IFS= read -r match; do
            [ -z "$match" ] && continue
            local file=$(echo "$match" | cut -d: -f1)
            local line_num=$(echo "$match" | cut -d: -f2)
            finding "$label in $file (line $line_num)"
            count=$((count + 1))
            TOTAL_FINDINGS=$((TOTAL_FINDINGS + 1))
        done < <(eval "find $dir -maxdepth 5 -type f \\( $FILE_TYPES \\) -print0 2>/dev/null" | \
                 xargs -0 grep -nP "$pattern" 2>/dev/null | head -100)
    done

    if [ "$count" -eq 0 ]; then
        ok "No $label found"
    else
        warn "Found $count $label matches"
    fi
}

info "Scanning directories: $SCAN_DIRS"
echo ""

info "Scanning for SSNs (XXX-XX-XXXX)..."
scan_pattern "SSN" '\b[0-9]{3}-[0-9]{2}-[0-9]{4}\b'

info "Scanning for credit card numbers (16 digits)..."
scan_pattern "Credit Card" '\b(?:4[0-9]{3}|5[1-5][0-9]{2}|3[47][0-9]{2}|6(?:011|5[0-9]{2}))[- ]?[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}\b'

info "Scanning for email addresses..."
scan_pattern "Email" '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'

info "Scanning for US phone numbers..."
scan_pattern "Phone" '\b(?:\+?1[-. ]?)?\(?[0-9]{3}\)?[-. ][0-9]{3}[-. ][0-9]{4}\b'

echo ""
if [ "$TOTAL_FINDINGS" -gt 0 ]; then
    warn "Total PII findings: $TOTAL_FINDINGS"
    warn "Review and remediate before competition scoring"
else
    ok "No PII found in scanned directories"
fi
