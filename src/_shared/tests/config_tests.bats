#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/config_tests.bats
# Tests for _devbot_get_config — the canonical config getter with
# project-first, global-fallback precedence — and its wrappers
# _devbot_get_project_dir / _devbot_get_harness.
#
# Run from project root:
#   bats src/_shared/tests/config_tests.bats
#
# Regression: commit_memory was previously read from .devbot.project.jsonc
# only; a value set in .devbot.global.jsonc was ignored. _devbot_get_config
# merges the global config as a fallback (explicit project value wins).
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

# ── _devbot_get_config ──────────────────────────────────────────────────────

@test "_devbot_get_config falls back to global when project key is absent (commit_memory bug)" {
  _write_global_cfg '{ "commit_memory": true }'
  # project config exists but does not declare the key (template-like)
  _write_project_cfg '{ "project_name": "demo" }'

  run _devbot_get_config "commit_memory" "${PROJECT_DIR}"
  assert_success
  assert_output "true"
}

@test "_devbot_get_config falls back to global when project config file is missing" {
  _write_global_cfg '{ "commit_memory": true }'

  run _devbot_get_config "commit_memory" "${PROJECT_DIR}"
  assert_success
  assert_output "true"
}

@test "_devbot_get_config lets an explicit project false win over global true" {
  _write_global_cfg '{ "commit_memory": true }'
  _write_project_cfg '{ "commit_memory": false }'

  run _devbot_get_config "commit_memory" "${PROJECT_DIR}"
  assert_success
  assert_output "false"
}

@test "_devbot_get_config lets an explicit project true win over global false" {
  _write_global_cfg '{ "commit_memory": false }'
  _write_project_cfg '{ "commit_memory": true }'

  run _devbot_get_config "commit_memory" "${PROJECT_DIR}"
  assert_success
  assert_output "true"
}

@test "_devbot_get_config returns project value when global config is absent" {
  _write_project_cfg '{ "commit_memory": true }'

  run _devbot_get_config "commit_memory" "${PROJECT_DIR}"
  assert_success
  assert_output "true"
}

@test "_devbot_get_config returns empty when key is unset in both configs" {
  run _devbot_get_config "commit_memory" "${PROJECT_DIR}"
  assert_success
  assert_output ""
}

# ── _devbot_get_project_dir (wrapper) ───────────────────────────────────────

@test "_devbot_get_project_dir defaults to .agents when unset everywhere" {
  run _devbot_get_project_dir "${PROJECT_DIR}"
  assert_success
  assert_output ".agents"
}

@test "_devbot_get_project_dir lets project value win over global" {
  _write_project_cfg '{ "devbot_dir": ".dev" }'
  _write_global_cfg '{ "devbot_dir": ".glob" }'

  run _devbot_get_project_dir "${PROJECT_DIR}"
  assert_success
  assert_output ".dev"
}

@test "_devbot_get_project_dir falls back to global value" {
  _write_global_cfg '{ "devbot_dir": ".glob" }'

  run _devbot_get_project_dir "${PROJECT_DIR}"
  assert_success
  assert_output ".glob"
}

# ── _devbot_get_harness (wrapper) ───────────────────────────────────────────

@test "_devbot_get_harness passes through a valid value" {
  _write_project_cfg '{ "harness": "claudecode" }'

  run _devbot_get_harness "${PROJECT_DIR}"
  assert_success
  assert_output "claudecode"
}

@test "_devbot_get_harness defaults to opencode for an invalid value" {
  _write_project_cfg '{ "harness": "bogus" }'

  run _devbot_get_harness "${PROJECT_DIR}"
  assert_success
  assert_output "opencode"
}

@test "_devbot_get_harness falls back to global value" {
  _write_project_cfg '{ "project_name": "demo" }'
  _write_global_cfg '{ "harness": "claudecode" }'

  run _devbot_get_harness "${PROJECT_DIR}"
  assert_success
  assert_output "claudecode"
}
