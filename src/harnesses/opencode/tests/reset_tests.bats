#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode/tests/reset_tests.bats
# Tests for opencode/reset.sh:
#   - harness disabled -> .opencode/ and opencode.jsonc left UNTOUCHED
#     (the user may use opencode independently of dev-bot)
#   - harness enabled  -> dev-bot symlinks removed, user files kept
#
# Runs the REAL reset.sh against a sandbox project dir whose
# .devbot.project.jsonc explicitly sets the opencode module state.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "${TEST_DIR}/../../../.." && pwd)"
  RESET_SCRIPT="${PROJECT_ROOT}/src/harnesses/opencode/reset.sh"

  SANDBOX_DIR="$(mktemp -d)"

  command -v python3 &>/dev/null || skip "python3 not installed"
  command -v jq &>/dev/null || skip "jq not installed"
  command -v bash &>/dev/null || skip "bash not installed"
}

teardown() {
  rm -rf "${SANDBOX_DIR}" 2>/dev/null || true
}

# _write_project_config <enabled|disabled>: write .devbot.project.jsonc with
# the opencode module explicitly set, overriding the global default.
_write_project_config() {
  local state="$1"
  local value=false
  [[ "${state}" == "enabled" ]] && value=true

  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<JSONC_EOF
{
  "modules": {
    "opencode": ${value}
  }
}
JSONC_EOF
}

# _create_opencode_dir: realistic user .opencode/ with a user agent file and a
# dev-bot symlink (pointing into the real repo).
_create_opencode_dir() {
  mkdir -p "${SANDBOX_DIR}/.opencode/agents"
  echo "# User agent" > "${SANDBOX_DIR}/.opencode/agents/user-agent.md"
  ln -s "${PROJECT_ROOT}/src/agentic/devbot/agents" "${SANDBOX_DIR}/.opencode/agents/devbot"
  cat > "${SANDBOX_DIR}/opencode.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "devbot-tools": {"type": "local", "command": ["x"]},
    "qmd": {"type": "local", "command": ["qmd", "mcp"], "environment": {"QMD_LLAMA_GPU": true}}
  }
}
JSONC_EOF
}

# ── Disabled harness: leave everything untouched ───────────────────────────

@test "disabled: leaves .opencode/ and opencode.jsonc intact" {
  _write_project_config disabled
  _create_opencode_dir

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  assert [ -d "${SANDBOX_DIR}/.opencode" ]
  assert [ -f "${SANDBOX_DIR}/.opencode/agents/user-agent.md" ]
  assert [ -L "${SANDBOX_DIR}/.opencode/agents/devbot" ]
  assert [ -f "${SANDBOX_DIR}/opencode.jsonc" ]
}

@test "disabled: does not remove dev-bot symlinks either" {
  _write_project_config disabled
  _create_opencode_dir

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  assert [ -L "${SANDBOX_DIR}/.opencode/agents/devbot" ]
}

@test "disabled: skips gracefully when nothing exists" {
  _write_project_config disabled

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success
}

# ── Enabled harness: surgical cleanup only ─────────────────────────────────

@test "enabled: removes dev-bot symlinks but keeps user files and opencode.jsonc" {
  _write_project_config enabled
  _create_opencode_dir

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  # dev-bot symlink removed
  refute [ -L "${SANDBOX_DIR}/.opencode/agents/devbot" ]
  # user artifacts preserved
  assert [ -f "${SANDBOX_DIR}/.opencode/agents/user-agent.md" ]
  assert [ -f "${SANDBOX_DIR}/opencode.jsonc" ]
  assert [ -d "${SANDBOX_DIR}/.opencode" ]
}

@test "enabled: skips when no .opencode/ directory" {
  _write_project_config enabled

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success
}

# ── audit-28 review F1: reset must drop the stale qmd MCP entry ─────────────

@test "enabled: removes devbot-tools AND qmd MCP keys from opencode.jsonc" {
  _write_project_config enabled
  _create_opencode_dir

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  # Both keys removed so reinit re-registers them fresh from module templates
  # (the qmd env changed in audit-28: QMD_LLAMA_GPU boolean -> placeholder +
  # QMD_EXPAND_CONTEXT_SIZE — existing configs kept the stale entry).
  run python3 -c "
import json, sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
d = load_jsonc('${SANDBOX_DIR}/opencode.jsonc')
mcp = d.get('mcp', {})
assert 'devbot-tools' not in mcp, mcp
assert 'qmd' not in mcp, mcp
print('MCP-CLEAN:OK')
"
  assert_success
  grep -qF 'MCP-CLEAN:OK' <<< "$output" || fail "MCP keys not removed"
}
