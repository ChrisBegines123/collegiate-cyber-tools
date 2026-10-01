#!/usr/bin/env bats
# Tests for ../user_priv_audit.sh.
#
# The script inspects live system state (getent passwd, id, passwd -S,
# sudo -l, /etc/shadow), so these tests stub out getent/id/passwd/sudo via
# PATH and point them at fixtures under ./fixtures, instead of touching the
# real account database.

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../user_priv_audit.sh"
    STUBS="$BATS_TEST_DIRNAME/stubs"
    FIXTURES="$BATS_TEST_DIRNAME/fixtures"
    PATH="$STUBS:$PATH"
    export PATH

    export FAKE_UID=1000
    export FAKE_PASSWD_FILE="$FIXTURES/passwd_basic"
    export FAKE_GROUPS_FILE="$FIXTURES/groups_basic"
    export FAKE_PASSWD_STATUS_FILE="$FIXTURES/passwd_status_basic"
    unset FAKE_SUDOERS_FILE
    unset FAKE_ACTIONS_LOG
    unset SUDO_USER
}

@test "lists root and human accounts at/above the min UID, excluding system accounts" {
    run sh "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"root"* ]]
    [[ "$output" == *"alice"* ]]
    [[ "$output" == *"bob"* ]]
    [[ "$output" == *"carol"* ]]
    [[ "$output" != *"daemon"* ]]
}

@test "-m raises the minimum UID threshold" {
    run sh "$SCRIPT" -m 1002
    [ "$status" -eq 0 ]
    [[ "$output" != *"alice"* ]]
    [[ "$output" != *"bob"* ]]
    [[ "$output" == *"carol"* ]]
}

@test "flags a non-root account with UID 0" {
    run sh "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[!] WARNING: non-root account with UID 0: evil"* ]]
}

@test "reports group-based sudo access and lock status per account" {
    run sh "$SCRIPT"
    [ "$status" -eq 0 ]
    # alice: active password, in the sudo group
    [[ "$output" =~ alice[[:space:]]+1000[[:space:]]+1000[[:space:]]+alice,sudo[[:space:]]+/bin/bash[[:space:]]+active[[:space:]]+yes\(group\) ]]
    # bob: locked password, no privileged group
    [[ "$output" =~ bob[[:space:]]+1001[[:space:]]+1001[[:space:]]+bob[[:space:]]+/bin/bash[[:space:]]+LOCKED[[:space:]]+no ]]
    # carol: no password set, in the wheel group
    [[ "$output" =~ carol[[:space:]]+1002[[:space:]]+1002[[:space:]]+carol,wheel[[:space:]]+/bin/bash[[:space:]]+NO_PASS[[:space:]]+yes\(group\) ]]
}

@test "non-root run notes incomplete sudoers/shadow checks and skips sudo -l" {
    FAKE_UID=1000
    run sh "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NOTE: not running as root; sudoers/shadow checks will be incomplete."* ]]
    # bob has no group-based sudo access, and sudoers lookup is skipped as non-root
    [[ "$output" =~ bob[[:space:]]+1001[[:space:]]+1001[[:space:]]+bob[[:space:]]+/bin/bash[[:space:]]+LOCKED[[:space:]]+no ]]
}

@test "root run checks sudoers and grants yes(sudoers) for a listed non-group account" {
    export FAKE_UID=0
    export FAKE_SUDOERS_FILE="$BATS_TEST_TMPDIR/sudoers.lst"
    printf 'bob\n' > "$FAKE_SUDOERS_FILE"

    run sh "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" != *"NOTE: not running as root"* ]]
    [[ "$output" =~ bob[[:space:]]+1001[[:space:]]+1001[[:space:]]+bob[[:space:]]+/bin/bash[[:space:]]+LOCKED[[:space:]]+yes\(sudoers\) ]]
}

@test "always prints the shadow anomalies section header" {
    run sh "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"=== Password hash anomalies (/etc/shadow) ==="* ]]
}

@test "-l diffs the account list against an expected user file" {
    run sh "$SCRIPT" -l "$FIXTURES/expected_users.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Present on system but NOT in expected list"* ]]
    [[ "$output" =~ \[!\][[:space:]]*carol ]]
    [[ "$output" =~ \[!\][[:space:]]*evil ]]
    [[ "$output" == *"MISSING from system"* ]]
    [[ "$output" =~ \[!\][[:space:]]*dave ]]
}

@test "-l with an unreadable file fails with a clear error" {
    run sh "$SCRIPT" -l "$BATS_TEST_TMPDIR/does-not-exist.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot read expected list"* ]]
}

@test "without -a, remediation is dry-run only and no mutating command runs" {
    export FAKE_UID=0
    export FAKE_ACTIONS_LOG="$BATS_TEST_TMPDIR/actions.log"

    run sh "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY-RUN] would lock+expire+kill sessions for evil (non-root account with UID 0)"* ]]
    # log_action() still records the dry-run intent via the logger stub, but
    # none of the actual mutating commands (passwd/usermod/pkill/gpasswd) run.
    ! grep -qE '^(passwd -l|usermod -e|pkill|gpasswd -d)' "$FAKE_ACTIONS_LOG" 2>/dev/null
}

@test "-a as root locks, expires, and kills sessions for a non-root UID 0 clone" {
    export FAKE_UID=0
    export FAKE_ACTIONS_LOG="$BATS_TEST_TMPDIR/actions.log"

    run sh "$SCRIPT" -a
    [ "$status" -eq 0 ]
    [[ "$output" == *"[ACTION] locked, expired, and killed sessions for evil"* ]]
    grep -qx "passwd -l evil" "$FAKE_ACTIONS_LOG"
    grep -q "^usermod -e 1 evil$" "$FAKE_ACTIONS_LOG"
    grep -q "^pkill .*evil$" "$FAKE_ACTIONS_LOG"
}

@test "-a without root refuses to remediate and says so" {
    export FAKE_UID=1000
    export FAKE_ACTIONS_LOG="$BATS_TEST_TMPDIR/actions.log"

    run sh "$SCRIPT" -a
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cannot remediate evil (non-root account with UID 0): not running as root"* ]]
    ! grep -qx "passwd -l evil" "$FAKE_ACTIONS_LOG" 2>/dev/null
}

@test "-a never locks the root account even if it's flagged" {
    export FAKE_UID=0
    export FAKE_ACTIONS_LOG="$BATS_TEST_TMPDIR/actions.log"
    no_root_list="$BATS_TEST_TMPDIR/expected_no_root.txt"
    printf 'alice\nbob\ndave\n' > "$no_root_list"

    run sh "$SCRIPT" -a -l "$no_root_list"
    [ "$status" -eq 0 ]
    [[ "$output" == *"REFUSING to lock root account"* ]]
    ! grep -qx "passwd -l root" "$FAKE_ACTIONS_LOG"
}

@test "-a never touches the account the audit itself is running as" {
    export FAKE_UID=0
    export SUDO_USER=evil
    export FAKE_ACTIONS_LOG="$BATS_TEST_TMPDIR/actions.log"

    run sh "$SCRIPT" -a
    [ "$status" -eq 0 ]
    [[ "$output" == *"REFUSING to lock the account running this audit (evil"* ]]
    ! grep -qx "passwd -l evil" "$FAKE_ACTIONS_LOG" 2>/dev/null
}

@test "-p with -a strips a privileged group the expected-privileges file doesn't authorize" {
    export FAKE_UID=0
    export FAKE_ACTIONS_LOG="$BATS_TEST_TMPDIR/actions.log"

    run sh "$SCRIPT" -a -p "$FIXTURES/expected_privs.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"UNAUTHORIZED PRIVILEGE: carol is in 'wheel' but not authorized for it"* ]]
    grep -qx "gpasswd -d carol wheel" "$FAKE_ACTIONS_LOG"
    # alice is authorized for sudo, so no group is stripped from her
    ! grep -q "gpasswd -d alice" "$FAKE_ACTIONS_LOG" 2>/dev/null
}

@test "-l with -a locks accounts that aren't in the expected user list" {
    export FAKE_UID=0
    export FAKE_ACTIONS_LOG="$BATS_TEST_TMPDIR/actions.log"

    run sh "$SCRIPT" -a -l "$FIXTURES/expected_users.txt"
    [ "$status" -eq 0 ]
    grep -qx "passwd -l carol" "$FAKE_ACTIONS_LOG"
    grep -qx "passwd -l evil" "$FAKE_ACTIONS_LOG"
}

@test "-o writes action log entries to the given logfile" {
    export FAKE_UID=0
    export FAKE_ACTIONS_LOG="$BATS_TEST_TMPDIR/actions.log"
    logfile="$BATS_TEST_TMPDIR/audit.log"

    run sh "$SCRIPT" -a -o "$logfile"
    [ "$status" -eq 0 ]
    [ -f "$logfile" ]
    grep -q "account=evil" "$logfile"
    grep -q 'result=success' "$logfile"
}

@test "rejects an unknown option with usage and exit 1" {
    run sh "$SCRIPT" -z
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "exits with a clear error when getent is unavailable" {
    real_sh="$(command -v sh)"
    mindir="$BATS_TEST_TMPDIR/minimal-bin"
    mkdir -p "$mindir"
    ln -s "$real_sh" "$mindir/sh"
    PATH="$mindir"

    run "$mindir/sh" "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"getent not found; cannot continue"* ]]
}
