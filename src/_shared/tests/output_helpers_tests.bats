#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/output_helpers_tests.bats
# Output helpers must emit no ANSI colour unless stdout is a terminal.
#
# audit-75 NOTE-6: `devbot module list` piped to a non-TTY still emitted raw
# `\x1b[1m\x1b[0;34m`, so captured/piped output was polluted with escape codes.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

@test "colour is empty when stdout is not a TTY (piped/captured)" {
  # `run` captures stdout, so it is not a terminal — the branch under test.
  run bash -c "source '${PROJECT_ROOT}/src/_shared/functions.sh'; printf '%s%s' \"\${TEXT_BOLD}\" \"\${TEXT_BLUE}\""
  assert_success
  assert_output ""
}

@test "NO_COLOR forces colour off" {
  run env NO_COLOR=1 bash -c "source '${PROJECT_ROOT}/src/_shared/functions.sh'; printf '%s' \"\${TEXT_BOLD}\""
  assert_success
  assert_output ""
}

@test "_ok output carries no escape sequence when piped" {
  run bash -c "source '${PROJECT_ROOT}/src/_shared/functions.sh'; _ok hello"
  assert_success
  [[ "$output" != *$'\033'* ]] || fail "escape sequence leaked into piped output: $output"
  assert_output --partial "hello"
}

@test "FORCE_COLOR restores colour for a non-TTY stream" {
  run env FORCE_COLOR=1 bash -c "source '${PROJECT_ROOT}/src/_shared/functions.sh'; printf '%s' \"\${TEXT_BOLD}\""
  assert_success
  # TEXT_BOLD holds the literal escape *source* (\033[1m), interpreted only by
  # `echo -e` — so assert the value, not an actual ESC byte.
  [ "${output}" = '\033[1m' ] || fail "FORCE_COLOR did not restore colour: ${output}"
}

@test "FORCE_COLOR=0 does not force colour" {
  run env FORCE_COLOR=0 bash -c "source '${PROJECT_ROOT}/src/_shared/functions.sh'; printf '%s' \"\${TEXT_BOLD}\""
  assert_success
  assert_output ""
}

@test "NO_COLOR wins over FORCE_COLOR" {
  run env NO_COLOR=1 FORCE_COLOR=1 bash -c "source '${PROJECT_ROOT}/src/_shared/functions.sh'; printf '%s' \"\${TEXT_BOLD}\""
  assert_success
  assert_output ""
}
