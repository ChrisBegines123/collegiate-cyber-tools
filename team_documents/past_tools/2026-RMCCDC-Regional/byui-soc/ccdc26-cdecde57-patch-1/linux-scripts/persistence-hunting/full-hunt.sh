#!/bin/bash
# Brady Hodge - CCDC26 Linux Toolkit - Full Persistence Hunt
# Run all persistence hunting scripts

source "$(dirname "$0")/../utils/common.sh"
require_root

SCRIPT_DIR="$(dirname "$0")"

header "CCDC26 Full Persistence Hunt"

START_TIME=$(date +%s)

header "Phase 1: Cron Job Audit"
bash "$SCRIPT_DIR/cron-audit.sh" <<< "7"

header "Phase 2: Service Audit"
bash "$SCRIPT_DIR/service-audit.sh" <<< "8"

header "Phase 3: User Audit"
bash "$SCRIPT_DIR/user-audit.sh" <<< "11"

header "Phase 4: Binary Audit"
bash "$SCRIPT_DIR/binary-audit.sh" <<< "9"

header "Phase 5: Startup Audit"
bash "$SCRIPT_DIR/startup-audit.sh" <<< "10"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

header "Persistence Hunt Complete"
success "Full hunt completed in $DURATION seconds"

echo ""
echo "Review findings in:"
echo "  - /var/log/ccdc-toolkit/findings.log"
echo ""
echo "To clean up findings, use individual scripts with cleanup options."

log_action "Full persistence hunt completed"
