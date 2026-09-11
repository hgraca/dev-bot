#!/usr/bin/env bats
# =============================================================================
# bin/tests/byte_idempotency_report_tests.bats
# Tests for the e2e byte-idempotency evidence writer.
#
# `devbot reinit` must be byte-idempotent. The fixture launcher runs the double
# reinit BEFORE the harness starts (test-reinit.sh) and records the verdict plus
# per-file SHA-256 byte values to .agents/logs/byte-idempotency.log, so the
# in-session audit can report PASS/FAIL from captured evidence instead of
# NOT-RUN. The writer lives in tests/test-project/test-lib.sh; here it runs
# against temp files (no docker).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  LIB="${REPO_ROOT}/tests/test-project/test-lib.sh"

  SANDBOX="$(mktemp -d)"
  SNAP="${SANDBOX}/snap"
  LIVE="${SANDBOX}/live"
  LOG="${SANDBOX}/byte-idempotency.log"
  mkdir -p "${SNAP}" "${LIVE}"

  # shellcheck source=/dev/null
  source "${LIB}"
}

teardown() {
  rm -rf "${SANDBOX}"
}

@test "PASS when every generated file is byte-identical after reinit #2" {
  printf 'a\n' > "${SNAP}/AGENTS.md"
  printf 'a\n' > "${LIVE}/AGENTS.md"
  printf '{"x":1}\n' > "${SNAP}/opencode.jsonc"
  printf '{"x":1}\n' > "${LIVE}/opencode.jsonc"

  run byte_idempotency_report "${SNAP}" "${LIVE}" "${LOG}" AGENTS.md opencode.jsonc

  assert_success
  assert_output --partial "BYTE-IDEMPOTENCY-PASS"

  # The captured evidence carries the per-file byte values (reinit1/reinit2)
  # and a MATCH verdict for each.
  run cat "${LOG}"
  assert_output --partial "AGENTS.md"
  assert_output --partial "opencode.jsonc"
  assert_output --partial "MATCH"
  assert_output --partial "BYTE-IDEMPOTENCY-PASS"
  run grep -c 'MATCH' "${LOG}"
  assert_output "2"
}

@test "FAIL when a generated file changes on the second reinit" {
  printf 'a\n' > "${SNAP}/AGENTS.md"
  printf 'b\n' > "${LIVE}/AGENTS.md"

  run byte_idempotency_report "${SNAP}" "${LIVE}" "${LOG}" AGENTS.md

  assert_failure
  assert_output --partial "BYTE-IDEMPOTENCY-FAIL"

  run cat "${LOG}"
  assert_output --partial "DIFF"
  assert_output --partial "BYTE-IDEMPOTENCY-FAIL"
}

@test "FAIL when a snapshotted file is missing after reinit #2" {
  printf 'a\n' > "${SNAP}/CLAUDE.md"

  run byte_idempotency_report "${SNAP}" "${LIVE}" "${LOG}" CLAUDE.md

  assert_failure
  run cat "${LOG}"
  assert_output --partial "MISSING"
  assert_output --partial "BYTE-IDEMPOTENCY-FAIL"
}

@test "files absent from the reinit #1 snapshot are not reported" {
  printf 'a\n' > "${SNAP}/AGENTS.md"
  printf 'a\n' > "${LIVE}/AGENTS.md"

  run byte_idempotency_report "${SNAP}" "${LIVE}" "${LOG}" AGENTS.md .mcp.json

  assert_success
  run cat "${LOG}"
  assert_output --partial "AGENTS.md"
  refute_output --partial ".mcp.json"
}
