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
