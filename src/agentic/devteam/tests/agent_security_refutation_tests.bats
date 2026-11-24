#!/usr/bin/env bats
# =============================================================================
# src/agentic/devteam/tests/agent_security_refutation_tests.bats
# The refutation pass is the separation of duties between finding and judging.
# It only works if both sides of it are written down and neither side silently
# claims the other's job.
# =============================================================================

setup() {
    bats_load_library bats-support
    bats_load_library bats-assert

    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    ROOT="$(cd "${TEST_DIR}/../../../.." && pwd)"
    CRITIC="${ROOT}/src/agentic/devteam/agents/critic.md"
    SECURITY="${ROOT}/src/agentic/devteam/agents/security.md"
}

@test "critic carries a security findings refutation mode" {
    run grep -qF '### Security Findings Refutation' "$CRITIC"
    assert_success
    run grep -qF 'SECURITY-REFUTE-' "$CRITIC"
    assert_success
}

@test "critic takes the records from the prompt, keeping the write-first gate" {
    # The opener gate requires the first tool call to be the report write, so
    # the findings cannot be read from disk. The mode must say where they come
    # from, or a critic following it will stall on the gate.
    run bash -c "tr '\n' ' ' <'${CRITIC}' | grep -qi 'Context section'"
    assert_success
    run bash -c "tr '\n' ' ' <'${CRITIC}' | grep -qi 'first tool call'"
    assert_success
}

@test "critic defers the verdict vocabulary to the record skill" {
    run grep -qF 'devbot:security-findings' "$CRITIC"
    assert_success
    run bash -c "tr '\n' ' ' <'${CRITIC}' | grep -qi 'apply it, do not redefine it'"
    assert_success
}

@test "the refutation asks reachability and guard before severity" {
    # Order matters: severity is meaningless before the path is shown to exist.
    local reachable guard severity
    reachable="$(grep -n 'Reachability' "$CRITIC" | head -1 | cut -d: -f1)"
    guard="$(grep -n 'Guard on the release path' "$CRITIC" | head -1 | cut -d: -f1)"
    severity="$(grep -n 'Severity earned' "$CRITIC" | head -1 | cut -d: -f1)"
    [ -n "${reachable}" ] && [ -n "${guard}" ] && [ -n "${severity}" ]
    [ "${reachable}" -lt "${guard}" ] && [ "${guard}" -lt "${severity}" ]
}

@test "security names the refutation pass and refuses to run it itself" {
    run grep -qF '## Refutation' "$SECURITY"
    assert_success
    run bash -c "tr '\n' ' ' <'${SECURITY}' | grep -qi 'task.*denied to this agent'"
    assert_success
    run bash -c "tr '\n' ' ' <'${SECURITY}' | grep -qi 'has not been refuted; it has been written'"
    assert_success
}

@test "security decides what a rejection may and may not do" {
    local verdict
    for verdict in uphold downgrade reject unverifiable; do
        run grep -qF "\`${verdict}\`" "$SECURITY"
        assert_success
    done
    # A rejection is not the same as evidence.
    run bash -c "tr '\n' ' ' <'${SECURITY}' | grep -qi 'restates the concern is not evidence'"
    assert_success
}
