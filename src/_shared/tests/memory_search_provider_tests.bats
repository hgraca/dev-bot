#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/memory_search_provider_tests.bats
# Tests for _devbot_get_memory_search_provider and the qmd/mdctx mutual
# exclusion added to _devbot_get_disabled_modules.
#
# The two memory-search engine modules are interchangeable: which one is
# active is chosen by the global-only key "memory_search_provider"
# (.devbot.global.jsonc), absent => mdctx. The non-selected engine module is
# auto-appended to the disabled set, so every lifecycle/registration consumer
# honours the swap. The qmd/mdctx pair is independent of (and orthogonal to)
# the codebase-index/codebase-memory pair — both unions apply.
#
# Run from project root:
#   bats src/_shared/tests/memory_search_provider_tests.bats
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

# ── _devbot_get_memory_search_provider ───────────────────────────────────────

@test "_devbot_get_memory_search_provider defaults to mdctx when key absent" {
  _write_global_cfg '{ "gpu_enabled": true }'

  run _devbot_get_memory_search_provider "${PROJECT_DIR}"
  assert_success
  assert_output "mdctx"
}

@test "_devbot_get_memory_search_provider defaults to mdctx when config file missing" {
  run _devbot_get_memory_search_provider "${PROJECT_DIR}"
  assert_success
  assert_output "mdctx"
}

@test "_devbot_get_memory_search_provider passes through mdctx" {
  _write_global_cfg '{ "memory_search_provider": "mdctx" }'

  run _devbot_get_memory_search_provider "${PROJECT_DIR}"
  assert_success
  assert_output "mdctx"
}

@test "_devbot_get_memory_search_provider passes through qmd" {
  _write_global_cfg '{ "memory_search_provider": "qmd" }'

  run _devbot_get_memory_search_provider "${PROJECT_DIR}"
  assert_success
  assert_output "qmd"
}

@test "_devbot_get_memory_search_provider defaults to mdctx for an invalid value" {
  _write_global_cfg '{ "memory_search_provider": "bogus-engine" }'

  run _devbot_get_memory_search_provider "${PROJECT_DIR}"
  assert_success
  assert_output "mdctx"
}

# ── _devbot_get_disabled_modules: memory-engine mutual exclusion ─────────────
# Each fixture pins codebase_index_provider explicitly so the codebase pair's
# auto-disable is deterministic and the expected set isolates the memory pair.

@test "disabled set auto-disables mdctx when provider is qmd" {
  _write_global_cfg '{
    "codebase_index_provider": "codebase-index",
    "memory_search_provider": "qmd"
  }'

  run _devbot_get_disabled_modules "${PROJECT_DIR}"
  assert_success
  assert_output '["codebase-memory", "mdctx"]'
}

@test "disabled set auto-disables qmd when provider is mdctx" {
  _write_global_cfg '{
    "codebase_index_provider": "codebase-index",
    "memory_search_provider": "mdctx"
  }'

  run _devbot_get_disabled_modules "${PROJECT_DIR}"
  assert_success
  assert_output '["codebase-memory", "qmd"]'
}

@test "disabled set auto-disables qmd when memory_search_provider absent (default mdctx)" {
  _write_global_cfg '{ "codebase_index_provider": "codebase-index" }'

  run _devbot_get_disabled_modules "${PROJECT_DIR}"
  assert_success
  assert_output '["codebase-memory", "qmd"]'
}

@test "disabled set keeps explicit modules-map disables alongside both auto-disables" {
  _write_global_cfg '{
    "codebase_index_provider": "codebase-index",
    "memory_search_provider": "qmd",
    "modules": { "graphify": false }
  }'

  run _devbot_get_disabled_modules "${PROJECT_DIR}"
  assert_success
  assert_output '["codebase-memory", "graphify", "mdctx"]'
}

@test "explicit false on the selected memory engine still disables it (no memory engine)" {
  _write_global_cfg '{
    "codebase_index_provider": "codebase-index",
    "memory_search_provider": "qmd",
    "modules": { "qmd": false }
  }'

  run _devbot_get_disabled_modules "${PROJECT_DIR}"
  assert_success
  assert_output '["codebase-memory", "mdctx", "qmd"]'
}

@test "both memory engines explicitly false => both disabled (no memory engine)" {
  _write_global_cfg '{
    "codebase_index_provider": "codebase-index",
    "memory_search_provider": "qmd",
    "modules": { "qmd": false, "mdctx": false }
  }'

  run _devbot_get_disabled_modules "${PROJECT_DIR}"
  assert_success
  assert_output '["codebase-memory", "mdctx", "qmd"]'
}

@test "project modules-map disable of the selected memory engine wins over global provider" {
  _write_global_cfg '{
    "codebase_index_provider": "codebase-index",
    "memory_search_provider": "qmd"
  }'
  _write_project_cfg '{ "modules": { "qmd": false } }'

  run _devbot_get_disabled_modules "${PROJECT_DIR}"
  assert_success
  assert_output '["codebase-memory", "mdctx", "qmd"]'
}

# ── Orthogonality with the codebase pair ─────────────────────────────────────

@test "memory pair and codebase pair auto-disable independently" {
  # codebase_index_provider absent => codebase-memory (adds codebase-index);
  # memory_search_provider qmd => adds mdctx. Both unions apply.
  _write_global_cfg '{ "memory_search_provider": "qmd" }'

  run _devbot_get_disabled_modules "${PROJECT_DIR}"
  assert_success
  assert_output '["codebase-index", "mdctx"]'
}

@test "codebase pair resolves independently when only codebase_index_provider is set" {
  # memory_search_provider absent => mdctx (adds qmd); codebase-index => adds
  # codebase-memory. Both unions apply.
  _write_global_cfg '{ "codebase_index_provider": "codebase-index" }'

  run _devbot_get_disabled_modules "${PROJECT_DIR}"
  assert_success
  assert_output '["codebase-memory", "qmd"]'
}
