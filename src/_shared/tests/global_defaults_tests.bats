#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/global_defaults_tests.bats
# Tests for _devbot_ensure_global_default — the `devbot update` provider pin:
# adds a scalar key with a legacy default to .devbot.global.jsonc ONLY when the
# key is absent (never overwrites an existing value, comment-preserving text
# insert).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SANDBOX_DIR="$(mktemp -d)"

  command -v python3 &>/dev/null || skip "python3 not installed"

  mkdir -p "${SANDBOX_DIR}/src/_shared"
  cp "${PROJECT_ROOT}/src/_shared/read_jsonc.py" "${SANDBOX_DIR}/src/_shared/read_jsonc.py"

  export DEV_BOT_ROOT="${SANDBOX_DIR}"
  # shellcheck source=../functions.sh
  source "${PROJECT_ROOT}/src/_shared/functions.sh"
}

teardown() {
  rm -rf "${SANDBOX_DIR}" 2>/dev/null || true
}

_write_global_cfg() {
  printf '%s\n' "$1" > "${SANDBOX_DIR}/.devbot.global.jsonc"
}

_reader_value() {
  python3 "${SANDBOX_DIR}/src/_shared/read_jsonc.py" "${SANDBOX_DIR}/.devbot.global.jsonc" "$1"
}

@test "adds an absent key with the legacy value (codebase-index)" {
  _write_global_cfg '{ "gpu_enabled": true }'

  run _devbot_ensure_global_default codebase_index_provider codebase-index
  assert_success

  run _reader_value codebase_index_provider
  assert_success
  assert_output "codebase-index"
}

@test "adds an absent key with the legacy value (qmd)" {
  _write_global_cfg '{ "gpu_enabled": true }'

  run _devbot_ensure_global_default memory_search_provider qmd
  assert_success

  run _reader_value memory_search_provider
  assert_success
  assert_output "qmd"
}

@test "leaves an existing key untouched (any value)" {
  _write_global_cfg '{ "codebase_index_provider": "codebase-memory", "memory_search_provider": "mdctx" }'

  run _devbot_ensure_global_default codebase_index_provider codebase-index
  assert_success
  run _devbot_ensure_global_default memory_search_provider qmd
  assert_success

  run _reader_value codebase_index_provider
  assert_output "codebase-memory"
  run _reader_value memory_search_provider
  assert_output "mdctx"
}

@test "no-op when the file is missing" {
  run _devbot_ensure_global_default codebase_index_provider codebase-index
  assert_failure
}

@test "inserts after the first top-level key, preserving comments and other keys" {
  _write_global_cfg '{
  // engine selection
  "gpu_enabled": true,
  "modules": {}
}'

  run _devbot_ensure_global_default memory_search_provider qmd
  assert_success
  run _devbot_ensure_global_default codebase_index_provider codebase-index
  assert_success

  # The comment + original keys survive, and both new keys resolve.
  run _reader_value gpu_enabled
  assert_output "true"
  run _reader_value memory_search_provider
  assert_output "qmd"
  run _reader_value codebase_index_provider
  assert_output "codebase-index"
}
