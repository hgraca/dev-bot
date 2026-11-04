#!/usr/bin/env bats
# =============================================================================
# src/agentic/netsuite/tests/netsuite_tests.bats
# Tests for the netsuite module.
#
# The module is a declaration + per-project init: `netsuite.account_id` (project
# over global) builds the account URL, and init.sh emits harness-native dynamic
# MCP manifests named `netsuite-<account>`. The server ships disabled — opencode
# keeps it wired-but-not-started so it is connected from the harness; claudecode
# omits a disabled server from .mcp.json.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "${TEST_DIR}/.." && pwd)"
  INIT="${MODULE_DIR}/init.sh"

  command -v jq &>/dev/null || skip "jq not installed"

  TMP="$(mktemp -d)"
  export DEV_BOT_ROOT="${TMP}/devbot"
  mkdir -p "${DEV_BOT_ROOT}"
  PROJECT="${TMP}/project"
  mkdir -p "${PROJECT}"
  : > "${DEV_BOT_ROOT}/.devbot.global.jsonc"
}

teardown() {
  rm -rf "${TMP}"
}

set_global() { printf '%s\n' "$1" > "${DEV_BOT_ROOT}/.devbot.global.jsonc"; }
set_project() { printf '%s\n' "$1" > "${PROJECT}/.devbot.project.jsonc"; }

# Print one manifest entry as sorted JSON, so a test can assert it exactly.
entry() {
  python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
print(json.dumps(data[sys.argv[2]], sort_keys=True))
' "$1" "$2"
}

URL_BASE="suitetalk.api.netsuite.com/services/mcp/v1/all"

# ── emission ─────────────────────────────────────────────────────────────────

@test "registers netsuite-<account> disabled, OAuth auto-detected" {
  set_global '{"netsuite": {"account_id": "1234567"}}'

  run bash "${INIT}" "${PROJECT}"
  assert_success

  [ -f "${PROJECT}/.opencode/netsuite-1234567.mcp.json" ]
  run entry "${PROJECT}/.opencode/netsuite-1234567.mcp.json" "netsuite-1234567"
  assert_output '{"enabled": false, "type": "remote", "url": "https://1234567.'"${URL_BASE}"'"}'
}

@test "normalises a sandbox account id the way NetSuite's hostname does" {
  set_global '{"netsuite": {"account_id": "1234567_SB1"}}'

  run bash "${INIT}" "${PROJECT}"
  assert_success

  [ -f "${PROJECT}/.opencode/netsuite-1234567-sb1.mcp.json" ]
  run entry "${PROJECT}/.opencode/netsuite-1234567-sb1.mcp.json" "netsuite-1234567-sb1"
  assert_output '{"enabled": false, "type": "remote", "url": "https://1234567-sb1.'"${URL_BASE}"'"}'
}

@test "registers the claudecode server disabled in the mcpServers shape" {
  set_global '{"netsuite": {"account_id": "1234567"}}'

  run bash "${INIT}" "${PROJECT}"
  assert_success

  [ -f "${PROJECT}/.claude/netsuite-1234567.mcp.json" ]
  run python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))["mcpServers"]["netsuite-1234567"]
print(json.dumps(data, sort_keys=True))
' "${PROJECT}/.claude/netsuite-1234567.mcp.json"
  assert_output '{"enabled": false, "type": "http", "url": "https://1234567.'"${URL_BASE}"'"}'
}

@test "netsuite.enabled true registers both servers enabled" {
  set_global '{"netsuite": {"account_id": "1234567", "enabled": true}}'

  run bash "${INIT}" "${PROJECT}"
  assert_success

  run entry "${PROJECT}/.opencode/netsuite-1234567.mcp.json" "netsuite-1234567"
  assert_output --partial '"enabled": true'
  run python3 -c '
import json, sys
print(json.load(open(sys.argv[1]))["mcpServers"]["netsuite-1234567"]["enabled"])
' "${PROJECT}/.claude/netsuite-1234567.mcp.json"
  assert_output "True"
}

# ── precedence ───────────────────────────────────────────────────────────────

@test "a project account id overrides the global one" {
  set_global '{"netsuite": {"account_id": "1111111"}}'
  set_project '{"netsuite": {"account_id": "2222222"}}'

  run bash "${INIT}" "${PROJECT}"
  assert_success

  run entry "${PROJECT}/.opencode/netsuite-2222222.mcp.json" "netsuite-2222222"
  assert_output --partial '"url": "https://2222222.'"${URL_BASE}"'"'
}

@test "a project enabled flag overrides the global one" {
  set_global '{"netsuite": {"account_id": "1234567", "enabled": true}}'
  set_project '{"netsuite": {"enabled": false}}'

  run bash "${INIT}" "${PROJECT}"
  assert_success

  run entry "${PROJECT}/.opencode/netsuite-1234567.mcp.json" "netsuite-1234567"
  assert_output --partial '"enabled": false'
}

# ── absent / invalid ─────────────────────────────────────────────────────────

@test "skips quietly and names the config key when the account id is unset" {
  run bash "${INIT}" "${PROJECT}"
  assert_success

  [ ! -e "${PROJECT}/.opencode" ]
  [ ! -e "${PROJECT}/.claude" ]
  assert_output --partial "netsuite.account_id"
  refute_output --partial "WARN"
}

@test "rejects a malformed account id instead of building a broken URL" {
  set_global '{"netsuite": {"account_id": "bad/../host"}}'

  run bash "${INIT}" "${PROJECT}"
  assert_success

  [ ! -e "${PROJECT}/.opencode" ]
  assert_output --partial "not a valid NetSuite account ID"
}

@test "prunes the manifests and registered key when the account id is removed" {
  set_global '{"netsuite": {"account_id": "1234567"}}'
  run bash "${INIT}" "${PROJECT}"
  assert_success

  printf '{\n  "mcp": {\n    "netsuite-1234567": { "type": "remote", "url": "x" },\n    "other": { "type": "remote", "url": "y" }\n  }\n}\n' \
    > "${PROJECT}/opencode.jsonc"

  set_global '{}'
  run bash "${INIT}" "${PROJECT}"
  assert_success

  [ ! -f "${PROJECT}/.opencode/netsuite-1234567.mcp.json" ]
  [ ! -f "${PROJECT}/.claude/netsuite-1234567.mcp.json" ]
  run python3 -c '
import json, sys
print(sorted(json.load(open(sys.argv[1]))["mcp"]))
' "${PROJECT}/opencode.jsonc"
  assert_output "['other']"
}

@test "changing the account id prunes the previous account's server" {
  set_global '{"netsuite": {"account_id": "1111111"}}'
  run bash "${INIT}" "${PROJECT}"
  assert_success

  printf '{\n  "mcp": {\n    "netsuite-1111111": { "type": "remote", "url": "x" },\n    "other": { "type": "remote", "url": "y" }\n  }\n}\n' \
    > "${PROJECT}/opencode.jsonc"

  set_global '{"netsuite": {"account_id": "2222222"}}'
  run bash "${INIT}" "${PROJECT}"
  assert_success

  [ ! -f "${PROJECT}/.opencode/netsuite-1111111.mcp.json" ]
  [ ! -f "${PROJECT}/.claude/netsuite-1111111.mcp.json" ]
  [ -f "${PROJECT}/.opencode/netsuite-2222222.mcp.json" ]
  # The harness registers the new server after module inits; the stale key for
  # the old account must be gone and unrelated servers untouched.
  run python3 -c '
import json, sys
print(sorted(json.load(open(sys.argv[1]))["mcp"]))
' "${PROJECT}/opencode.jsonc"
  assert_output "['other']"
}

@test "does nothing when the module is disabled for the project" {
  set_global '{"modules": {"netsuite": false}, "netsuite": {"account_id": "1234567"}}'

  run bash "${INIT}" "${PROJECT}"
  assert_success

  [ ! -e "${PROJECT}/.opencode" ]
  [ ! -e "${PROJECT}/.claude" ]
}

# ── module declarations ──────────────────────────────────────────────────────

@test "mcp.dynamic.json claims the netsuite server-key prefix" {
  [ -f "${MODULE_DIR}/mcp.dynamic.json" ]
  run python3 -c '
import json, sys
print(json.load(open(sys.argv[1]))["prefixes"])
' "${MODULE_DIR}/mcp.dynamic.json"
  assert_output --partial "netsuite"
}

@test "external-modules.json declares Oracle's official skills repository" {
  [ -f "${MODULE_DIR}/external-modules.json" ]
  run python3 -c '
import json, sys
entry = json.load(open(sys.argv[1]))["netsuite-suitecloud"]
assert entry["url"].endswith("oracle/netsuite-suitecloud-sdk.git"), entry
assert entry["paths"]["skills"] == "packages/agent-skills", entry
print("OK")
' "${MODULE_DIR}/external-modules.json"
  assert_output "OK"
}

@test "docs.md declares the module page and its MCP capability" {
  [ -f "${MODULE_DIR}/docs.md" ]
  run head -1 "${MODULE_DIR}/docs.md"
  assert_output "---"
  run grep -q '^title: ' "${MODULE_DIR}/docs.md"
  assert_success
  run grep -q '^mcps:' "${MODULE_DIR}/docs.md"
  assert_success
  run grep -q 'netsuite-account_id' "${MODULE_DIR}/docs.md"
  assert_success
}
