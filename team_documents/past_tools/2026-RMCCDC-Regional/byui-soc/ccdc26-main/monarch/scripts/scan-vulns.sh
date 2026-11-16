#!/bin/bash
# CCDC26 Monarch - Nuclei CVE Scanner
# Downloads and runs ProjectDiscovery Nuclei to scan local services for known CVEs.
# SELF-CONTAINED -- handles install, templates, scanning, and summary.
# Usage: scan-vulns.sh [target]   (defaults to localhost)

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; PURPLE='\033[0;35m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
phase() { echo -e "\n${BOLD}${PURPLE}[PHASE] $1${NC}\n"; }

if [ "$EUID" -ne 0 ]; then error "Must be run as root"; exit 1; fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT="/tmp/nuclei-scan-${TIMESTAMP}.txt"
TARGET="${1:-}"; NUCLEI_BIN="/usr/local/bin/nuclei"; FW_OPENED=false

# --- Temporary firewall opening (locked-down CCDC environments) -----------
fw_open() {
    if command -v iptables &>/dev/null; then
        info "Opening outbound 80/443 for download..."
        iptables -I OUTPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null
        iptables -I OUTPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null
        FW_OPENED=true
    fi
}
fw_close() {
    if [ "$FW_OPENED" = true ] && command -v iptables &>/dev/null; then
        info "Closing temporary outbound rules..."
        iptables -D OUTPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null
        iptables -D OUTPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null
        FW_OPENED=false
    fi
}
trap fw_close EXIT

# --- Phase 1: Install Nuclei -----------------------------------------------
phase "1 - Install Nuclei"
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)  DL_ARCH="amd64" ;;
    aarch64|arm64) DL_ARCH="arm64" ;;
    *) error "Unsupported architecture: $ARCH"; exit 1 ;;
esac
info "Architecture: ${ARCH} -> ${DL_ARCH}"

if [ ! -x "$NUCLEI_BIN" ]; then
    fw_open
    VER=$(curl -sI https://github.com/projectdiscovery/nuclei/releases/latest \
        | grep -i '^location:' | grep -oP 'v\K[0-9.]+')
    DL_URL="https://github.com/projectdiscovery/nuclei/releases/latest/download/nuclei_${VER}_linux_${DL_ARCH}.zip"
    TMPZIP=$(mktemp /tmp/nuclei-XXXX.zip)
    info "Downloading nuclei ${VER}..."
    if curl -fsSL --connect-timeout 10 -o "$TMPZIP" "$DL_URL" 2>/dev/null; then
        unzip -o "$TMPZIP" nuclei -d /usr/local/bin/ >/dev/null 2>&1
        chmod +x "$NUCLEI_BIN"; rm -f "$TMPZIP"
        ok "Nuclei installed: $("$NUCLEI_BIN" -version 2>&1 | head -1)"
    else
        rm -f "$TMPZIP"; fw_close
        if command -v nuclei &>/dev/null; then
            NUCLEI_BIN=$(command -v nuclei)
            warn "Download failed; using existing nuclei at ${NUCLEI_BIN}"
        else
            error "Cannot download nuclei and no existing install found"; exit 1
        fi
    fi
else
    ok "Nuclei already installed: $("$NUCLEI_BIN" -version 2>&1 | head -1)"
fi

# --- Phase 2: Update Templates ---------------------------------------------
phase "2 - Update Nuclei Templates"
if "$NUCLEI_BIN" -update-templates 2>&1 | tail -3; then
    ok "Templates updated"
else
    warn "Template update failed (offline?) -- using cached templates"
fi
fw_close

# --- Phase 3: Build Target List --------------------------------------------
phase "3 - Build Target List"
TARGETS_FILE=$(mktemp /tmp/nuclei-targets-XXXX.txt)
if [ -n "$TARGET" ]; then
    info "Remote target: ${TARGET}"
    echo "$TARGET" > "$TARGETS_FILE"
else
    info "Scanning localhost -- detecting listening services..."
    while IFS= read -r port; do
        case "$port" in
            443|8443|9443) echo "https://localhost:${port}" ;;
            *)             echo "http://localhost:${port}" ;;
        esac
    done < <(ss -tlnp 2>/dev/null | awk 'NR>1 {print $4}' | grep -oP '\d+$' | sort -un) > "$TARGETS_FILE"
fi
if [ ! -s "$TARGETS_FILE" ]; then
    warn "No listening services detected; adding common defaults"
    printf '%s\n' "http://localhost:80" "https://localhost:443" "http://localhost:8080" > "$TARGETS_FILE"
fi
info "Targets:"; sed 's/^/  → /' "$TARGETS_FILE"

# --- Phase 4: Run Nuclei Scan ----------------------------------------------
phase "4 - Nuclei CVE Scan"
info "Scanning... output -> ${REPORT}"
"$NUCLEI_BIN" -l "$TARGETS_FILE" \
    -severity critical,high,medium \
    -t cves/ -t vulnerabilities/ \
    -timeout 10 -rate-limit 50 \
    -silent -no-color -o "$REPORT" 2>/dev/null
rm -f "$TARGETS_FILE"

# --- Phase 5: Summary ------------------------------------------------------
phase "5 - Scan Summary"
if [ -s "$REPORT" ]; then
    CRIT=$(grep -ci '\[critical\]' "$REPORT" 2>/dev/null || echo 0)
    HIGH=$(grep -ci '\[high\]'     "$REPORT" 2>/dev/null || echo 0)
    MED=$(grep -ci '\[medium\]'    "$REPORT" 2>/dev/null || echo 0)
    echo -e "${RED}  Critical : ${CRIT}${NC}"
    echo -e "${YELLOW}  High     : ${HIGH}${NC}"
    echo -e "${BLUE}  Medium   : ${MED}${NC}"
    echo -e "  ${BOLD}Total    : $((CRIT + HIGH + MED))${NC}\n"
    ok "Full report: ${REPORT}"
    # Common CCDC remediation hints
    grep -qi 'log4j\|log4shell'                "$REPORT" 2>/dev/null && warn "REMEDIATE: Log4Shell -- upgrade log4j >= 2.17.1 or set LOG4J_FORMAT_MSG_NO_LOOKUPS=true"
    grep -qi 'spring4shell\|CVE-2022-22965'    "$REPORT" 2>/dev/null && warn "REMEDIATE: Spring4Shell -- upgrade Spring >= 5.3.18"
    grep -qi 'CVE-2023-44487\|rapid-reset'     "$REPORT" 2>/dev/null && warn "REMEDIATE: HTTP/2 Rapid Reset -- update web server / load balancer"
    grep -qi 'CVE-2024-3094\|xz-backdoor'      "$REPORT" 2>/dev/null && warn "REMEDIATE: XZ backdoor -- downgrade xz-utils < 5.6.0"
    grep -qi 'heartbleed\|CVE-2014-0160'       "$REPORT" 2>/dev/null && warn "REMEDIATE: Heartbleed -- upgrade OpenSSL >= 1.0.1g"
    grep -qi 'shellshock\|CVE-2014-6271'       "$REPORT" 2>/dev/null && warn "REMEDIATE: Shellshock -- update bash"
else
    ok "No critical/high/medium vulnerabilities found"
    info "Report (empty): ${REPORT}"
fi
info "Done. Scan completed in ${SECONDS}s"
