#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/jsonc_gate_tests.bats
# Tests _devbot_require_valid_jsonc — the pre-launch gate that refuses to start
# the harness on a config it cannot parse.
#
# Why it exists: v2config.py's _insert once wrote a doubled comma, leaving
# opencode.jsonc unparseable. Nothing looked at the file before the harness
# booted, so the session came up with none of the servers it declares and no
# message saying why.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  PROJECT_ROOT="$(cd "${TEST_DIR}/../../.." && pwd)"
  WORK="$(mktemp -d)"
  # shellcheck source=../functions.sh
  source "${PROJECT_ROOT}/src/_shared/functions.sh"
}

teardown() {
  rm -rf "${WORK}"
}

@test "a valid config passes silently" {
  printf '{ "mcp": { "servers": {} } }\n' >"${WORK}/opencode.jsonc"
  run _devbot_require_valid_jsonc "${WORK}/opencode.jsonc"
  assert_success
  assert_output ""
}

@test "comments and a single trailing comma are valid JSONC" {
  printf '{\n  // a comment\n  "a": 1,\n}\n' >"${WORK}/opencode.jsonc"
  run _devbot_require_valid_jsonc "${WORK}/opencode.jsonc"
  assert_success
}

@test "the doubled comma that cost a whole reinit fails loudly" {
  printf '{ "mcp": { "servers": { "a": { "type": "local" },, } } }\n' >"${WORK}/opencode.jsonc"
  run _devbot_require_valid_jsonc "${WORK}/opencode.jsonc"
  assert_failure
  assert_output --partial "FATAL"
  assert_output --partial "opencode.jsonc is not valid JSONC"
}

@test "the parser's own message is shown, not just the verdict" {
  printf '{ "a": }\n' >"${WORK}/opencode.jsonc"
  run _devbot_require_valid_jsonc "${WORK}/opencode.jsonc"
  assert_failure
  assert_output --partial "ERROR:"
  # The real parser line, not a canned refusal that would pass a looser match.
  assert_output --partial "opencode.jsonc:"
  assert_output --partial "Expecting"
}

@test "an unterminated block comment is refused, not read as end-of-file" {
  # The stripper used to truncate at an unterminated `/*`, so a config the
  # harness cannot parse came back valid and the launch gate let it through.
  printf '{ "mcp": { "servers": {} } } /* unterminated\n' >"${WORK}/opencode.jsonc"
  run _devbot_require_valid_jsonc "${WORK}/opencode.jsonc"
  assert_failure
  assert_output --partial "FATAL"
  assert_output --partial "unterminated block comment"
}

@test "a non-UTF-8 config is refused rather than dumping a traceback" {
  printf '{ "a": "\xff" }\n' >"${WORK}/opencode.jsonc"
  run _devbot_require_valid_jsonc "${WORK}/opencode.jsonc"
  assert_failure
  assert_output --partial "FATAL"
  refute_output --partial "Traceback"
}

@test "a missing config is not an error: there is nothing to boot from badly" {
  run _devbot_require_valid_jsonc "${WORK}/absent.jsonc"
  assert_success
}

@test "an empty argument is not an error" {
  run _devbot_require_valid_jsonc ""
  assert_success
}
