#!/usr/bin/env bats
# =============================================================================
# src/agentic/atlassian/tests/atlassian_tests.bats
# Tests for the atlassian module — the official Atlassian Rovo MCP Server plus
# a first-party Jira workflow skill.
#
# The server is Atlassian's cloud-hosted Rovo MCP (https://mcp.atlassian.com),
# reached over streamable HTTP with OAuth 2.1. The module is a pure
# declaration: one canonical mcp.json (no host binary, no per-project init), so
# only the manifest shape and its translation are ours to guarantee.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
  TRANSLATE="${PROJECT_ROOT}/src/_shared/mcp_translate.py"
}

assert_json_eq() {
  # Compare two JSON blobs key-order-insensitively.
  assert_equal "$(jq -S . <<<"$1")" "$(jq -S . <<<"$2")"
}

# ── MCP manifest ─────────────────────────────────────────────────────────────

@test "canonical mcp.json declares the official Atlassian Rovo MCP server" {
  run python3 -c "
import json
d = json.load(open('${MODULE_DIR}/mcp.json'))
m = d['mcp']['atlassian']
assert m['type'] == 'http', m
assert m['url'] == 'https://mcp.atlassian.com/v2/mcp', m
assert 'command' not in m, m
assert 'env' not in m, m
# OAuth is opencode's auto-detected default: no explicit oauth key, so a 401
# triggers the 2.1 flow instead of being suppressed.
assert 'oauth' not in m, m
# Off by default: the module is opt-in and the server ships wired but not
# started, matching chrome-devtools/playwright/signoz.
assert m['enabled'] is False, m
print('MCP:OK')
"
  assert_success
  grep -qF 'MCP:OK' <<< "$output" || fail "canonical mcp.json shape wrong"
}

@test "MCP integration is a single canonical mcp.json, not a plugin" {
  [ -f "${MODULE_DIR}/mcp.json" ]
  [ ! -f "${MODULE_DIR}/mcp.opencode.json" ]
  [ ! -f "${MODULE_DIR}/mcp.claudecode.json" ]
  [ ! -f "${MODULE_DIR}/plugin.opencode.json" ]
}

# ── Translation ──────────────────────────────────────────────────────────────

@test "translates to opencode as a remote server (OAuth auto-detected)" {
  run python3 "$TRANSLATE" "${MODULE_DIR}/mcp.json" opencode
  assert_success
  assert_json_eq "$output" \
    '{"atlassian": {"type": "remote", "url": "https://mcp.atlassian.com/v2/mcp", "enabled": false}}'
}

@test "translates to claudecode as an http server" {
  run python3 "$TRANSLATE" "${MODULE_DIR}/mcp.json" claudecode
  assert_success
  assert_json_eq "$output" \
    '{"atlassian": {"type": "http", "url": "https://mcp.atlassian.com/v2/mcp"}}'
}

# ── Skill ────────────────────────────────────────────────────────────────────

@test "ships a discoverable devbot:atlassian skill with a trigger description" {
  local skill="${MODULE_DIR}/skills/SKILL.md"
  [ -f "$skill" ]
  run grep -q '^name: devbot:atlassian$' "$skill"
  assert_success
  # A missing/empty description silently drops the skill from the palette.
  run grep -q '^description: ' "$skill"
  assert_success
}
