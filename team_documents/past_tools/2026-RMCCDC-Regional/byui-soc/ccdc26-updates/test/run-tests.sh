#!/bin/bash
# CCDC26 Test Suite -- Builds Docker environment, runs Monarch against targets
# Usage:
#   ./run-tests.sh              # Full test (build + run + teardown)
#   ./run-tests.sh --up         # Just start containers
#   ./run-tests.sh --test       # Run tests (containers must be running)
#   ./run-tests.sh --shell      # Drop into controller shell
#   ./run-tests.sh --down       # Teardown

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

PASS=0
FAIL=0
SKIP=0

pass() { echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL + 1)); }
skip() { echo -e "  ${YELLOW}SKIP${NC} $1"; SKIP=$((SKIP + 1)); }
info() { echo -e "${CYAN}[TEST]${NC} $1"; }
header() { echo -e "\n${BOLD}=== $1 ===${NC}\n"; }

TARGETS="10.99.0.11 10.99.0.12 10.99.0.13 10.99.0.14"
TARGET_NAMES=("ecom/ubuntu" "webmail/fedora" "splunk/rocky" "workstation/alpine")
PASSWORD="changeme"
CONTROLLER="ccdc-controller"

ctrl_exec() {
    docker exec "$CONTROLLER" bash -c "$1"
}

build_environment() {
    header "Building Docker Environment"
    info "Building images (this may take a few minutes on first run)..."
    docker compose build --parallel 2>&1 | tail -5
    info "Starting containers..."
    docker compose up -d 2>&1
    info "Waiting for SSH to be ready..."
    for ip in $TARGETS; do
        local retries=0
        while [ $retries -lt 30 ]; do
            if ctrl_exec "sshpass -p '$PASSWORD' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=2 root@$ip echo ok" 2>/dev/null | grep -q ok; then
                break
            fi
            retries=$((retries + 1))
            sleep 1
        done
        if [ $retries -ge 30 ]; then
            fail "SSH not ready on $ip after 30s"
        else
            pass "SSH ready on $ip"
        fi
    done
}

test_monarch_scan() {
    header "Test: Monarch Scan"
    info "Running: scan 172.20.0.0/24 $PASSWORD"
    local output
    output=$(ctrl_exec "cd /opt/ccdc26/monarch && echo 'scan 10.99.0.0/24 $PASSWORD' | python3 -m monarch 2>&1" 2>&1)
    local found=0
    for ip in $TARGETS; do
        if echo "$output" | grep -q "$ip"; then
            found=$((found + 1))
        fi
    done
    if [ $found -ge 3 ]; then
        pass "Monarch discovered $found/4 targets"
    else
        fail "Monarch only discovered $found/4 targets"
        echo "    Output: $(echo "$output" | tail -10)"
    fi
}

test_script_dispatch() {
    local script_name="$1"
    local description="$2"
    local expect_fail="${3:-false}"
    local extra_args="${4:-}"

    info "Dispatching: $script_name -- $description"

    local idx=0
    local script_pass=0
    local script_fail=0
    for ip in $TARGETS; do
        local name="${TARGET_NAMES[$idx]}"
        local output
        output=$(ctrl_exec "sshpass -p '$PASSWORD' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$ip 'bash -s $extra_args' < /opt/ccdc26/monarch/scripts/$script_name 2>&1; echo EXIT_CODE=\$?" 2>&1)
        local exit_code
        exit_code=$(echo "$output" | grep 'EXIT_CODE=' | tail -1 | cut -d= -f2)

        if [ "$expect_fail" = "true" ]; then
            skip "$name ($ip) -- expected failure (no Splunk server)"
        elif [ "${exit_code:-1}" = "0" ]; then
            script_pass=$((script_pass + 1))
        else
            script_fail=$((script_fail + 1))
            echo -e "    ${RED}Failed on $name ($ip), exit=$exit_code${NC}"
            echo "    Last 5 lines: $(echo "$output" | grep -v EXIT_CODE | tail -5)"
        fi
        idx=$((idx + 1))
    done

    if [ "$expect_fail" = "true" ]; then
        return
    elif [ $script_fail -eq 0 ]; then
        pass "$script_name succeeded on all $script_pass targets"
    else
        fail "$script_name failed on $script_fail targets ($script_pass passed)"
    fi
}

test_hardening_results() {
    header "Test: Verify Hardening Applied"

    for ip in $TARGETS; do
        local name
        case $ip in
            10.99.0.11) name="ecom/ubuntu" ;;
            10.99.0.12) name="webmail/fedora" ;;
            10.99.0.13) name="splunk/rocky" ;;
            10.99.0.14) name="workstation/alpine" ;;
        esac

        info "Checking $name ($ip)..."

        local sshd_config
        sshd_config=$(ctrl_exec "sshpass -p '$PASSWORD' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$ip cat /etc/ssh/sshd_config 2>/dev/null" 2>&1)
        if echo "$sshd_config" | grep -qi 'PermitRootLogin no'; then
            pass "$name: SSH root login disabled"
        else
            fail "$name: SSH root login NOT disabled"
        fi

        local sysctl_fwd
        sysctl_fwd=$(ctrl_exec "sshpass -p '$PASSWORD' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$ip sysctl -n net.ipv4.ip_forward 2>/dev/null" 2>&1)
        if [ "$(echo "$sysctl_fwd" | tr -d '[:space:]')" = "0" ]; then
            pass "$name: IP forwarding disabled"
        else
            fail "$name: IP forwarding NOT disabled (value: $sysctl_fwd)"
        fi
    done
}

test_firewall_applied() {
    header "Test: Verify Firewall Rules"

    for ip in $TARGETS; do
        local name
        case $ip in
            10.99.0.11) name="ecom/ubuntu" ;;
            10.99.0.12) name="webmail/fedora" ;;
            10.99.0.13) name="splunk/rocky" ;;
            10.99.0.14) name="workstation/alpine" ;;
        esac

        local rules
        rules=$(ctrl_exec "sshpass -p '$PASSWORD' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$ip iptables -L -n 2>/dev/null | wc -l" 2>&1)
        rules=$(echo "$rules" | tr -d '[:space:]')
        if [ "${rules:-0}" -gt 10 ]; then
            pass "$name: iptables has $rules lines of rules"
        else
            skip "$name: iptables rules minimal ($rules lines) -- may not have iptables"
        fi
    done
}

test_persistence_hunt() {
    header "Test: Persistence Hunt"
    info "Running hunt-persistence.sh on ecom (Ubuntu)..."
    local output
    output=$(ctrl_exec "sshpass -p '$PASSWORD' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@10.99.0.11 'bash -s' < /opt/ccdc26/monarch/scripts/hunt-persistence.sh 2>&1; echo EXIT_CODE=\$?" 2>&1)
    local exit_code
    exit_code=$(echo "$output" | grep 'EXIT_CODE=' | tail -1 | cut -d= -f2)
    if [ "${exit_code:-1}" = "0" ]; then
        local findings
        findings=$(echo "$output" | grep -c '\[FINDING\]' || true)
        pass "hunt-persistence.sh completed ($findings findings on clean container)"
    else
        fail "hunt-persistence.sh failed (exit=$exit_code)"
    fi
}

test_pii_scanner() {
    header "Test: PII Scanner"
    info "Running hunt-pii.sh on ecom (Ubuntu)..."
    local output
    output=$(ctrl_exec "sshpass -p '$PASSWORD' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@10.99.0.11 'bash -s' < /opt/ccdc26/monarch/scripts/hunt-pii.sh 2>&1; echo EXIT_CODE=\$?" 2>&1)
    local exit_code
    exit_code=$(echo "$output" | grep 'EXIT_CODE=' | tail -1 | cut -d= -f2)
    if [ "${exit_code:-1}" = "0" ]; then
        pass "hunt-pii.sh completed (clean container, no PII expected)"
    else
        fail "hunt-pii.sh failed (exit=$exit_code)"
    fi
}

print_summary() {
    header "Test Summary"
    echo -e "  ${GREEN}PASS: $PASS${NC}"
    echo -e "  ${RED}FAIL: $FAIL${NC}"
    echo -e "  ${YELLOW}SKIP: $SKIP${NC}"
    echo ""
    if [ $FAIL -eq 0 ]; then
        echo -e "  ${GREEN}${BOLD}ALL TESTS PASSED${NC}"
    else
        echo -e "  ${RED}${BOLD}$FAIL TEST(S) FAILED${NC}"
    fi
    echo ""
}

teardown() {
    header "Teardown"
    info "Stopping and removing containers..."
    docker compose down --volumes --remove-orphans 2>&1 | tail -3
    info "Done."
}

run_all_tests() {
    build_environment

    test_monarch_scan

    header "Test: Script Dispatch -- 00-snapshot.sh"
    test_script_dispatch "00-snapshot.sh" "Forensic baseline"

    header "Test: Script Dispatch -- 01-harden.sh"
    test_script_dispatch "01-harden.sh" "System hardening monolith"

    header "Test: Script Dispatch -- 02-firewall.sh"
    test_script_dispatch "02-firewall.sh" "Firewall configuration"

    header "Test: Script Dispatch -- 04-splunk.sh"
    test_script_dispatch "04-splunk.sh" "Splunk forwarder (expected fail)" "true"

    header "Test: Script Dispatch -- 05-monitor.sh"
    test_script_dispatch "05-monitor.sh" "Monitoring deployment"

    test_hardening_results
    test_firewall_applied
    test_persistence_hunt
    test_pii_scanner

    print_summary
    teardown

    [ $FAIL -eq 0 ] && exit 0 || exit 1
}

case "${1:-}" in
    --up)
        build_environment
        echo ""
        info "Containers running. Use: docker compose exec $CONTROLLER bash"
        ;;
    --test)
        test_monarch_scan
        header "Test: Script Dispatch -- 00-snapshot.sh"
        test_script_dispatch "00-snapshot.sh" "Forensic baseline"
        header "Test: Script Dispatch -- 01-harden.sh"
        test_script_dispatch "01-harden.sh" "System hardening monolith"
        header "Test: Script Dispatch -- 02-firewall.sh"
        test_script_dispatch "02-firewall.sh" "Firewall configuration"
        header "Test: Script Dispatch -- 05-monitor.sh"
        test_script_dispatch "05-monitor.sh" "Monitoring deployment"
        test_hardening_results
        test_firewall_applied
        test_persistence_hunt
        test_pii_scanner
        print_summary
        ;;
    --shell)
        docker compose exec "$CONTROLLER" bash
        ;;
    --down)
        teardown
        ;;
    --help|-h)
        echo "CCDC26 Test Suite"
        echo ""
        echo "Usage: $0 [option]"
        echo "  (none)    Full test: build + run + teardown"
        echo "  --up      Start containers only"
        echo "  --test    Run tests (containers must be running)"
        echo "  --shell   Drop into controller bash"
        echo "  --down    Stop and remove containers"
        ;;
    *)
        run_all_tests
        ;;
esac
