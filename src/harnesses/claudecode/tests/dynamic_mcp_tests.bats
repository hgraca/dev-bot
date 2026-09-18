#!/usr/bin/env bats
# =============================================================================
# src/harnesses/claudecode/tests/dynamic_mcp_tests.bats
# Tests for claudecode/init.sh's dynamic MCP wiring (_wire_mcp).
#
# Mirrors the opencode dynamic-MCP tests: a module init emits
# .claude/<name>.mcp.json for init-time values and _wire_mcp merges it into
# .mcp.json. A disabled module's init does not run, so a leftover manifest is
# stale and must not be wired.
#
# Runs the REAL init.sh against a sandbox project dir.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "${TEST_DIR}/../../../.." && pwd)"
  INIT_SCRIPT="${PROJECT_ROOT}/src/harnesses/claudecode/init.sh"

  SANDBOX_DIR="$(mktemp -d)"

  command -v python3 &>/dev/null || skip "python3 not installed"
  command -v jq &>/dev/null || skip "jq not installed"
  command -v bash &>/dev/null || skip "bash not installed"
}

teardown() {
  rm -rf "${SANDBOX_DIR}" 2>/dev/null || true
}

# _write_project_config <jetbrains-bool>: claudecode must be enabled for the
# harness init to wire anything, and the project map overrides the global one.
_write_project_config() {
  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<JSONC_EOF
{
  "modules": {
    "claudecode": true,
    "jetbrains": $1
  }
}
JSONC_EOF
}

# _put_manifest: the runtime manifest a jetbrains init would have emitted.
_put_manifest() {
  mkdir -p "${SANDBOX_DIR}/.claude"
  cat > "${SANDBOX_DIR}/.claude/jetbrains.mcp.json" <<'JSON_EOF'
{"mcpServers": {"jetbrains": {"type": "http", "url": "http://127.0.0.1:64442/stream", "enabled": true}}}
JSON_EOF
}

# _assert_mcp <present|absent>
_assert_mcp() {
  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
servers = load_jsonc('${SANDBOX_DIR}/.mcp.json').get('mcpServers', {})
present = 'jetbrains' in servers
assert present == (('$1' == 'present')), (present, servers)
print('DYN-CC-MCP:OK')
"
  assert_success
  grep -qF 'DYN-CC-MCP:OK' <<< "$output" || fail "jetbrains wiring state wrong (expected $1)"
}

@test "dynamic MCP: a disabled module's manifest is not wired" {
  _write_project_config false
  _put_manifest

  run bash "${INIT_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  _assert_mcp absent
}

@test "dynamic MCP: an enabled module's manifest is wired" {
  _write_project_config true
  _put_manifest

  run bash "${INIT_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  _assert_mcp present
}
