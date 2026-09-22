#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode/tests/dynamic_mcp_tests.bats
# Tests for opencode/init.sh's dynamic MCP registration (_register_dynamic_mcps).
#
# A module init emits .opencode/<name>.mcp.json for values only known at init
# time (jetbrains' detected IDE port) and the harness merges it into
# opencode.jsonc. A disabled module's init does not run, so any manifest it
# still owns is stale — registering it resurrects a server the user turned off.
# (A previous disable left the manifest on disk; the harness re-registered it
# on every init, so the server never actually went away.)
#
# Runs the REAL init.sh against a sandbox project dir whose
# .devbot.project.jsonc pins the module state.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "${TEST_DIR}/../../../.." && pwd)"
  INIT_SCRIPT="${PROJECT_ROOT}/src/harnesses/opencode/init.sh"

  SANDBOX_DIR="$(mktemp -d)"

  command -v python3 &>/dev/null || skip "python3 not installed"
  command -v jq &>/dev/null || skip "jq not installed"
  command -v bash &>/dev/null || skip "bash not installed"
}

teardown() {
  rm -rf "${SANDBOX_DIR}" 2>/dev/null || true
}

# _write_project_config <jetbrains-bool>: pin the module state at project level
# (project overrides the global maps, so the test is hermetic).
_write_project_config() {
  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<JSONC_EOF
{
  "modules": {
    "opencode": true,
    "jetbrains": $1
  }
}
JSONC_EOF
}

# _put_manifest: the runtime manifest a jetbrains init would have emitted.
_put_manifest() {
  mkdir -p "${SANDBOX_DIR}/.opencode"
  cat > "${SANDBOX_DIR}/.opencode/jetbrains.mcp.json" <<'JSON_EOF'
{"jetbrains": {"type": "remote", "url": "http://127.0.0.1:64442/stream", "enabled": true}}
JSON_EOF
}

# _put_manifest_with <enabled>: a manifest whose def can be made to differ from
# what a pre-existing config holds, so the upsert path is exercised.
_put_manifest_with() {
  mkdir -p "${SANDBOX_DIR}/.opencode"
  cat > "${SANDBOX_DIR}/.opencode/jetbrains.mcp.json" <<JSON_EOF
{"jetbrains": {"type": "remote", "url": "http://127.0.0.1:64442/stream", "enabled": $1}}
JSON_EOF
}

# _assert_mcp <present|absent>
_assert_mcp() {
  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
mcp = load_jsonc('${SANDBOX_DIR}/opencode.jsonc').get('mcp', {})
present = 'jetbrains' in mcp
assert present == (('$1' == 'present')), (present, mcp)
print('DYN-MCP:OK')
"
  assert_success
  grep -qF 'DYN-MCP:OK' <<< "$output" || fail "jetbrains registration state wrong (expected $1)"
}

@test "dynamic MCP: a disabled module's manifest is not registered" {
  _write_project_config false
  _put_manifest

  run bash "${INIT_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  assert_output --partial "jetbrains: disabled per config"
  _assert_mcp absent
}

@test "dynamic MCP: an enabled module's manifest is registered" {
  _write_project_config true
  _put_manifest

  run bash "${INIT_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  _assert_mcp present
}

@test "dynamic MCP: a changed manifest def replaces the registered entry" {
  # merge_mcp_jsonc.py is insert-only (SKIP_EXISTS), so a module that changes
  # the def it emits could never reach an existing config: the change would be
  # fresh-install-only. The config carries no `enabled` opinion, so the module's
  # declared default is introduced along with the new def.
  _write_project_config true
  _put_manifest_with false
  cat > "${SANDBOX_DIR}/opencode.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "jetbrains": { "type": "remote", "url": "http://127.0.0.1:64442/OLD" }
  }
}
JSONC_EOF

  run bash "${INIT_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
entry = load_jsonc('${SANDBOX_DIR}/opencode.jsonc')['mcp']['jetbrains']
assert entry['url'] == 'http://127.0.0.1:64442/stream', entry
print('UPSERTED:OK')
"
  assert_success
  grep -qF 'UPSERTED:OK' <<< "$output" || fail "stale dynamic def was not replaced"
}

@test "dynamic MCP: a config with no enabled opinion receives the module default" {
  # Propagation, isolated: nothing differs but the module newly declaring
  # `enabled: false`, and the entry must still be refreshed for it to land.
  _write_project_config true
  _put_manifest_with false
  cat > "${SANDBOX_DIR}/opencode.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "jetbrains": { "type": "remote", "url": "http://127.0.0.1:64442/stream" }
  }
}
JSONC_EOF

  run bash "${INIT_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
entry = load_jsonc('${SANDBOX_DIR}/opencode.jsonc')['mcp']['jetbrains']
assert entry.get('enabled') is False, entry
print('DEFAULT-LANDED:OK')
"
  assert_success
  grep -qF 'DEFAULT-LANDED:OK' <<< "$output" || fail "the module default did not reach a config with no opinion"
}

@test "dynamic MCP: a user's enabled choice is not undone by the module default" {
  # `enabled` is the user's switch. The module emitting `false` must not revert
  # a `true` the user set: the default-disabled servers are exactly the ones a
  # user switches on, and a routine reinit silently undoing it would make the
  # documented toggle useless.
  _write_project_config true
  _put_manifest_with false
  cat > "${SANDBOX_DIR}/opencode.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "jetbrains": { "type": "remote", "url": "http://127.0.0.1:64442/stream", "enabled": true }
  }
}
JSONC_EOF

  run bash "${INIT_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
entry = load_jsonc('${SANDBOX_DIR}/opencode.jsonc')['mcp']['jetbrains']
assert entry.get('enabled') is True, entry
print('USER-ENABLED-KEPT:OK')
"
  assert_success
  grep -qF 'USER-ENABLED-KEPT:OK' <<< "$output" || fail "the user's enabled choice was overwritten"
}

@test "dynamic MCP: a matching def is left in place (no churn, no reorder)" {
  # A removal re-appends the entry, so a def that already matches must not be
  # touched — otherwise every reinit reorders the mcp map. jetbrains must NOT be
  # last in the fixture: a re-append would land it back in the same place and
  # the ordering assertion would hold either way (a vacuous test).
  _write_project_config true
  _put_manifest_with false
  cat > "${SANDBOX_DIR}/opencode.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "mdctx": { "type": "remote", "url": "http://127.0.0.1:18501/mcp" },
    "jetbrains": { "type": "remote", "url": "http://127.0.0.1:64442/stream", "enabled": false },
    "tools-mcp": { "type": "remote", "url": "http://127.0.0.1:18505/mcp" }
  }
}
JSONC_EOF

  run bash "${INIT_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
keys = list(load_jsonc('${SANDBOX_DIR}/opencode.jsonc')['mcp'])
assert keys == ['mdctx', 'jetbrains', 'tools-mcp'], keys
print('NO-REORDER:OK')
"
  assert_success
  grep -qF 'NO-REORDER:OK' <<< "$output" || fail "a matching dynamic def was churned"

  # A second run leaves the file byte-identical (the reinit idempotency claim).
  local after_first
  after_first="$(cat "${SANDBOX_DIR}/opencode.jsonc")"

  run bash "${INIT_SCRIPT}" "${SANDBOX_DIR}"
  assert_success
  assert_equal "$(cat "${SANDBOX_DIR}/opencode.jsonc")" "${after_first}"
}
