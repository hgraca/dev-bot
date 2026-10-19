#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/set_jsonc_key_tests.bats
# Tests for the comment-preserving JSONC setter.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SETTER="${PROJECT_ROOT}/src/_shared/set_jsonc_key.py"
  READER="${PROJECT_ROOT}/src/_shared/read_jsonc.py"
  FILE="$(mktemp)"
}

teardown() {
  rm -f "${FILE}" 2>/dev/null || true
}

@test "inserts before a trailing line comment, not inside it" {
  printf '{\n  "model": "x" // user comment\n}\n' > "${FILE}"

  run python3 "${SETTER}" "${FILE}" lsp '{"intelephense":{}}'

  assert_success
  assert_output "SET"
  grep -q '// user comment' "${FILE}"
  run python3 "${READER}" "${FILE}" lsp
  assert_success
  assert_output --partial "intelephense"
}

@test "inserts before a trailing block comment" {
  printf '{\n  "model": "x" /* user */\n}\n' > "${FILE}"

  run python3 "${SETTER}" "${FILE}" lsp 'true'

  assert_success
  run python3 "${READER}" "${FILE}" lsp
  assert_success
  assert_output "true"
}

@test "adds the top-level key without overwriting a nested same-name key" {
  printf '{\n  "permission": {\n    "lsp": "allow"\n  }\n}\n' > "${FILE}"

  run python3 "${SETTER}" "${FILE}" lsp '{"intelephense":{}}'

  assert_success
  run python3 "${READER}" "${FILE}" permission lsp
  assert_success
  assert_output "allow"
  run python3 "${READER}" "${FILE}" lsp
  assert_success
  assert_output --partial "intelephense"
}

@test "inserts cleanly into an object without comments" {
  printf '{\n  "model": "x"\n}\n' > "${FILE}"

  run python3 "${SETTER}" "${FILE}" lsp 'true'

  assert_success
  run python3 "${READER}" "${FILE}" lsp
  assert_success
  assert_output "true"
}
