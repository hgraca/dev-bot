#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode-v2/tests/identity_wiring_tests.bats
# The call site the unit tests cannot reach: on-hooks-utils.test.ts covers
# stampShellCall in isolation, but deleting the call from the adapter would
# leave the whole suite green — and the defect it fixes (a subagent graded
# under its parent) needs a harness restart to observe live. This guards the
# wiring itself.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  HARNESS_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  ADAPTER="${HARNESS_DIR}/hooks/on-hooks.ts"
  UTILS="${HARNESS_DIR}/on-hooks-utils.ts"
}

@test "execute.before stamps the shell call with the calling identity" {
  run grep -F 'stampShellCall(' "${ADAPTER}"
  assert_success
  # The per-call agent, not only the context cache: the cache can miss, and the
  # code then unsets the name — grading the row as 'unknown'.
  run grep -F 'event?.agent' "${ADAPTER}"
  assert_success
  run grep -F 'event?.sessionID' "${ADAPTER}"
  assert_success
}

@test "the stamp is applied before the hook returns, after the guards run" {
  # Order matters twice: guards must match the command the model wrote, and the
  # rewrite has to happen while the event is still mutable.
  local stamp guard
  stamp="$(grep -n 'stampShellCall(' "${ADAPTER}" | cut -d: -f1 | head -1)"
  guard="$(grep -n 'guardDecision(out' "${ADAPTER}" | cut -d: -f1 | head -1)"
  assert [ -n "${stamp}" ]
  assert [ -n "${guard}" ]
  assert [ "${guard}" -lt "${stamp}" ]
}

@test "the helper mutates the call's input rather than returning a string" {
  run grep -F 'target.command = stamped' "${UTILS}"
  assert_success
}
