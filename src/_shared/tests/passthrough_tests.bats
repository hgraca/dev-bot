#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/passthrough_tests.bats
# Tests for _devbot_passthrough_args — the harness-args escape in the devbot
# CLI. When a bare `devbot` start carries `--`, everything after the FIRST
# `--` is forwarded verbatim to the underlying harness (opencode/claude) and
# everything before it is devbot's own (consumed, not forwarded). No `--` →
# all args forward unchanged (documented "unknown argument" behaviour).
#
# The helper prints one arg per line (bash 3.2-safe — no mapfile on macOS
# default bash); callers assemble an argv array with a while-read loop.
#
# Run from project root:
#   bats src/_shared/tests/passthrough_tests.bats
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
  source "${PROJECT_ROOT}/src/_shared/functions.sh"
}

# Capture the helper output into a bash argv array (same pattern cmd_harness
# uses — while-read, not mapfile, for bash 3.2 compatibility).
_capture() {
  PASSTHROUGH=()
  while IFS= read -r arg; do
    PASSTHROUGH+=("${arg}")
  done < <(_devbot_passthrough_args "$@")
}

@test "no -- forwards every arg unchanged" {
  _capture -c "two words" run
  assert_equal "${#PASSTHROUGH[@]}" "3"
  assert_equal "${PASSTHROUGH[0]}" "-c"
  assert_equal "${PASSTHROUGH[1]}" "two words"
  assert_equal "${PASSTHROUGH[2]}" "run"
}

@test "no args forwards nothing" {
  _capture
  assert_equal "${#PASSTHROUGH[@]}" "0"
}

@test "leading -- forwards the tail, dropping the separator" {
  _capture -- --help
  assert_equal "${#PASSTHROUGH[@]}" "1"
  assert_equal "${PASSTHROUGH[0]}" "--help"
}

@test "args before -- are consumed, only the tail is forwarded" {
  _capture run "task" -- -c "two words"
  assert_equal "${#PASSTHROUGH[@]}" "2"
  assert_equal "${PASSTHROUGH[0]}" "-c"
  assert_equal "${PASSTHROUGH[1]}" "two words"
}

@test "only the FIRST -- splits; later -- are literal tail args" {
  _capture foo -- bar -- baz
  assert_equal "${#PASSTHROUGH[@]}" "3"
  assert_equal "${PASSTHROUGH[0]}" "bar"
  assert_equal "${PASSTHROUGH[1]}" "--"
  assert_equal "${PASSTHROUGH[2]}" "baz"
}

@test "bare -- forwards nothing" {
  _capture run "task" --
  assert_equal "${#PASSTHROUGH[@]}" "0"
}

@test "flag-looking args before -- are consumed with the prefix" {
  _capture --print-logs -- --model fast
  assert_equal "${#PASSTHROUGH[@]}" "2"
  assert_equal "${PASSTHROUGH[0]}" "--model"
  assert_equal "${PASSTHROUGH[1]}" "fast"
}
