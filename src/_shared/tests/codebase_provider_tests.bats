#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/codebase_provider_tests.bats
# Tests for _devbot_get_codebase_provider and the codebase-index/codebase-memory
# mutual exclusion added to _devbot_get_disabled_modules.
#
# The two codebase engine modules are interchangeable: which one is active is
# chosen by the global-only key "codebase_index_provider" (.devbot.global.jsonc),
# absent => codebase-memory. The non-selected engine module is auto-appended to
# the disabled set, so every lifecycle/registration consumer honours the swap.
#
# Run from project root:
#   bats src/_shared/tests/codebase_provider_tests.bats
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SANDBOX_DIR="$(mktemp -d)"

  command -v python3 &>/dev/null || skip "python3 not installed"

  # The sandbox plays the devbot root: it holds the fixture global config plus
  # the real read_jsonc.py reader (both resolved via DEV_BOT_ROOT).
  mkdir -p "${SANDBOX_DIR}/src/_shared"
  cp "${PROJECT_ROOT}/src/_shared/read_jsonc.py" "${SANDBOX_DIR}/src/_shared/read_jsonc.py"

  export DEV_BOT_ROOT="${SANDBOX_DIR}"
  # shellcheck source=../functions.sh
  source "${PROJECT_ROOT}/src/_shared/functions.sh"

  # Per-test project dir with its own .devbot.project.jsonc
  PROJECT_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "${SANDBOX_DIR}" "${PROJECT_DIR}" 2>/dev/null || true
}

# ── Fixture helpers ──────────────────────────────────────────────────────────

# Write a global config into the sandbox (JSON body passed as $1).
_write_global_cfg() {
  printf '%s\n' "$1" > "${SANDBOX_DIR}/.devbot.global.jsonc"
}

# Write a project config into PROJECT_DIR (JSON body passed as $1).
_write_project_cfg() {
  printf '%s\n' "$1" > "${PROJECT_DIR}/.devbot.project.jsonc"
}

# ── _devbot_get_codebase_provider ───────────────────────────────────────────

@test "_devbot_get_codebase_provider defaults to codebase-memory when key absent" {
  _write_global_cfg '{ "gpu_enabled": true }'

  run _devbot_get_codebase_provider "${PROJECT_DIR}"
  assert_success
  assert_output "codebase-memory"
}

@test "_devbot_get_codebase_provider defaults to codebase-memory when config file missing" {
  run _devbot_get_codebase_provider "${PROJECT_DIR}"
  assert_success
  assert_output "codebase-memory"
}

@test "_devbot_get_codebase_provider passes through codebase-index" {
  _write_global_cfg '{ "codebase_index_provider": "codebase-index" }'

  run _devbot_get_codebase_provider "${PROJECT_DIR}"
  assert_success
  assert_output "codebase-index"
}

@test "_devbot_get_codebase_provider passes through codebase-memory" {
  _write_global_cfg '{ "codebase_index_provider": "codebase-memory" }'

  run _devbot_get_codebase_provider "${PROJECT_DIR}"
  assert_success
  assert_output "codebase-memory"
}

@test "_devbot_get_codebase_provider defaults to codebase-memory for an invalid value" {
  _write_global_cfg '{ "codebase_index_provider": "bogus-engine" }'

  run _devbot_get_codebase_provider "${PROJECT_DIR}"
  assert_success
  assert_output "codebase-memory"
}

# ── _devbot_get_disabled_modules: mutual exclusion ───────────────────────────

@test "disabled set auto-disables codebase-memory when provider is codebase-index" {
  _write_global_cfg '{ "codebase_index_provider": "codebase-index" }'

  run _devbot_get_disabled_modules "${PROJECT_DIR}"
  assert_success
  assert_output '["codebase-memory"]'
}

@test "disabled set auto-disables codebase-index when provider defaults to codebase-memory" {
  _write_global_cfg '{ "modules": {} }'

  run _devbot_get_disabled_modules "${PROJECT_DIR}"
  assert_success
  assert_output '["codebase-index"]'
}

@test "disabled set keeps explicit modules-map disables alongside the auto-disable" {
  _write_global_cfg '{ "codebase_index_provider": "codebase-memory", "modules": { "graphify": false } }'

  run _devbot_get_disabled_modules "${PROJECT_DIR}"
  assert_success
  assert_output '["codebase-index", "graphify"]'
}

@test "explicit false on the selected engine still disables it (no codebase engine)" {
  _write_global_cfg '{ "codebase_index_provider": "codebase-memory", "modules": { "codebase-memory": false } }'

  run _devbot_get_disabled_modules "${PROJECT_DIR}"
  assert_success
  assert_output '["codebase-index", "codebase-memory"]'
}

@test "both engines explicitly false => both disabled (no codebase engine)" {
  # Plan Task 1 acceptance: the "no codebase engine at all" configuration.
  # Explicit false adds each module; the auto-disable adds the other.
  _write_global_cfg '{
    "codebase_index_provider": "codebase-memory",
    "modules": { "codebase-index": false, "codebase-memory": false }
  }'

  run _devbot_get_disabled_modules "${PROJECT_DIR}"
  assert_success
  assert_output '["codebase-index", "codebase-memory"]'
}

@test "project modules-map disable of the selected engine wins over global provider" {
  _write_global_cfg '{ "codebase_index_provider": "codebase-index" }'
  _write_project_cfg '{ "modules": { "codebase-index": false } }'

  run _devbot_get_disabled_modules "${PROJECT_DIR}"
  assert_success
  assert_output '["codebase-index", "codebase-memory"]'
}
