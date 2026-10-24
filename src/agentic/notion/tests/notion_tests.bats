#!/usr/bin/env bats
# =============================================================================
# src/agentic/notion/tests/notion_tests.bats
# Tests for the notion module — Notion's official hosted MCP server plus a
# first-party read/write workflow skill.
#
# The server is Notion's cloud-hosted MCP (https://mcp.notion.com/mcp), reached
# over streamable HTTP with OAuth. The module is a pure declaration: one
# canonical mcp.json (no host binary, no per-project init), so only the manifest
# shape, its translation, and the docs are ours to guarantee.
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

@test "canonical mcp.json declares Notion's official hosted MCP server" {
  run python3 -c "
import json
d = json.load(open('${MODULE_DIR}/mcp.json'))
m = d['mcp']['notion']
assert m['type'] == 'http', m
assert m['url'] == 'https://mcp.notion.com/mcp', m
assert 'command' not in m, m
assert 'env' not in m, m
# OAuth is opencode's auto-detected default: no explicit oauth key, so a 401
# triggers the consent flow instead of being suppressed.
assert 'oauth' not in m, m
# Off by default: the module is opt-in and the server ships wired but not
# started, matching atlassian/chrome-devtools/signoz.
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
    '{"notion": {"type": "remote", "url": "https://mcp.notion.com/mcp", "enabled": false}}'
}

@test "mcp_translate renders it as an http server for claudecode" {
  # The translator only converts the shape. claudecode's init.sh then omits a
  # disabled server entirely — covered by its own dynamic_mcp_tests.bats.
  run python3 "$TRANSLATE" "${MODULE_DIR}/mcp.json" claudecode
  assert_success
  assert_json_eq "$output" \
    '{"notion": {"type": "http", "url": "https://mcp.notion.com/mcp"}}'
}

# ── Skill and docs ───────────────────────────────────────────────────────────

@test "ships a discoverable devbot:notion skill with a trigger description" {
  local skill="${MODULE_DIR}/skills/SKILL.md"
  [ -f "$skill" ]
  run grep -q '^name: devbot:notion$' "$skill"
  assert_success
  # A missing/empty description silently drops the skill from the palette.
  run grep -q '^description: ' "$skill"
  assert_success
}

@test "docs.md carries the front matter the docs build requires" {
  local docs="${MODULE_DIR}/docs.md"
  [ -f "$docs" ]
  run grep -q '^description: ' "$docs"
  assert_success
  # The docs front matter allows flow lists with or without quotes.
  run grep -qE '^skills: \["?notion"?\]$' "$docs"
  assert_success
  run grep -q '^  notion: ' "$docs"
  assert_success
}
