#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/global_value_tests.bats
# Tests for the raw-JSON global config writers in src/_shared/functions.sh:
#
#   _devbot_set_global_value <key> <raw-json>     — replace or insert a value
#   _devbot_ensure_global_value <key> <raw-json>  — insert only when absent
#
# Used by `devbot update` to write the boolean `auto_update` and the string
# `version` into .devbot.global.jsonc.
#
# Run from project root:
#   bats src/_shared/tests/global_value_tests.bats
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"

  export DEV_BOT_ROOT="$(mktemp -d)"
  source "${PROJECT_ROOT}/src/_shared/functions.sh"
  READER="${PROJECT_ROOT}/src/_shared/read_jsonc.py"
  CONFIG="${DEV_BOT_ROOT}/.devbot.global.jsonc"
}

teardown() {
  unset DEV_BOT_ROOT
  rm -rf "${DEV_BOT_ROOT}" 2>/dev/null || true
}

_write_config() {
  printf '%s\n' "$1" > "${CONFIG}"
}

_read() {
  python3 "${READER}" "${CONFIG}" "$1"
}

# ── _devbot_set_global_value ──────────────────────────────────────────────────

@test "set inserts a new key as the first property" {
  _write_config '{
  "harness": "opencode"
}'
  _devbot_set_global_value version '"1.4.0"'
  assert_equal "$(_read version)" "1.4.0"
  assert_equal "$(_read harness)" "opencode"
}

@test "set replaces an existing string value" {
  _write_config '{
  "version": "",
  "harness": "opencode"
}'
  _devbot_set_global_value version '"1.4.0"'
  assert_equal "$(_read version)" "1.4.0"
  assert_equal "$(_read harness)" "opencode"
}

@test "set preserves a trailing comment on the line" {
  _write_config '{
  "version": "", // set by update
  "harness": "opencode"
}'
  _devbot_set_global_value version '"2.0.0"'
  assert_equal "$(_read version)" "2.0.0"
  grep -q '// set by update' "${CONFIG}"
}

@test "set writes a boolean literal" {
  _write_config '{
  "auto_update": true
}'
  _devbot_set_global_value auto_update false
  assert_equal "$(_read auto_update)" "false"
}

@test "set inserts into an empty object" {
  _write_config '{}'
  _devbot_set_global_value version '"1.0.0"'
  assert_equal "$(_read version)" "1.0.0"
}

@test "set skips a leading comment when inserting the first key" {
  # A `{` inside a leading comment must not be mistaken for the object start.
  _write_config '// note { here
{
  "harness": "opencode"
}'
  _devbot_set_global_value version '"1.4.0"'
  assert_equal "$(_read version)" "1.4.0"
  assert_equal "$(_read harness)" "opencode"
}

@test "set fails when the config file is missing" {
  run _devbot_set_global_value version '"1.0.0"'
  assert_failure
}

# ── _devbot_ensure_global_value ───────────────────────────────────────────────

@test "ensure inserts the key when absent" {
  _write_config '{
  "harness": "opencode"
}'
  _devbot_ensure_global_value auto_update true
  assert_equal "$(_read auto_update)" "true"
}

@test "ensure leaves an existing value untouched" {
  _write_config '{
  "auto_update": false
}'
  _devbot_ensure_global_value auto_update true
  assert_equal "$(_read auto_update)" "false"
}

@test "ensure is a no-op when the key is already present" {
  _write_config '{
  "version": "1.0.0"
}'
  _devbot_ensure_global_value version '""'
  assert_equal "$(_read version)" "1.0.0"
}
