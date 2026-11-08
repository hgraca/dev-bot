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

@test "ships the devbot:jira-workflow skill with the four lifecycle touchpoints" {
local skill="${MODULE_DIR}/skills/jira-workflow/SKILL.md"
  [ -f "$skill" ]

run grep -q '^name: devbot:jira-workflow$' "$skill"
assert_success
run grep -q '^description: ' "$skill"
assert_success

# The lifecycle contract: resolve, open, PR prefix, close.

run grep -q 'before refinement' "$skill"
  assert_success
  run grep -q 'before implementation' "$skill"
assert_success
run grep -q 'PROJ-1234: ' "$skill"
  assert_success
  run grep -q 'CANCELED' "$skill"
assert_success

# Both gates are consulted through the tool, never by guessing.

run grep -q -- '--key mcps' "$skill"
  assert_success
  run grep -q -- '--key modules' "$skill"
assert_success
}

@test "ships the devbot:create-jira-issue skill with the type decision tree" {
local skill="${MODULE_DIR}/skills/create-jira-issue/SKILL.md"
  [ -f "$skill" ]

run grep -q '^name: devbot:create-jira-issue$' "$skill"
assert_success
run grep -q '^description: ' "$skill"
  assert_success
  for kind in Epic Story Task Subtask; do
    run grep -q "\*\*${kind}\*\*" "$skill"
assert_success
done

# Description mirrors the commit body, and Stream is epics-only.

run grep -q 'Problems:' "$skill"
  assert_success
  run grep -q 'Solutions:' "$skill"
assert_success
run grep -q '`Stream`' "$skill"
  assert_success
  run grep -qi 'epics only' "$skill"
assert_success
}

@test "ships the /create-jira-issue command forwarding to the skill" {
local command="${MODULE_DIR}/commands/create-jira-issue.md"
  [ -f "$command" ]

run grep -q '^name: devbot:create-jira-issue$' "$command"
assert_success
run grep -q 'devbot:create-jira-issue' "$command"
  assert_success
  run grep -q '\$ARGUMENTS' "$command"
assert_success
}

@test "docs manifest declares every skill and command the module ships" {
run python3 -c "
import re
text = open('${MODULE_DIR}/docs.md').read()
fm = text.split('---')[1]
assert 'skills: [\"atlassian\", \"jira-workflow\", \"create-jira-issue\"]' in fm, fm
assert 'commands: [\"create-jira-issue\"]' in fm, fm
print('DOCS:OK')
"
  assert_success
  grep -qF 'DOCS:OK' <<< "$output" || fail "docs.md manifest incomplete"
}
