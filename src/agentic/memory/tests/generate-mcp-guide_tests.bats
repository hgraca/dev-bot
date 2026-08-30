#!/usr/bin/env bats
# =============================================================================
# src/agentic/memory/tests/generate-mcp-guide_tests.bats
# Tests for generate-mcp-guide.sh — regenerates active/mcp.md from the LIVE
# harness MCP configs so the documented server list can't silently drift from
# what is actually registered (audit-20 FAIL: static fixture missed
# devbot-tools + jetbrains).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="$MODULE_DIR/tools/generate-mcp-guide.sh"

  WORK="$(mktemp -d)"
  OUT="$WORK/.agents/memory/active/mcp.md"
}

teardown() {
  rm -rf "$WORK"
}

# Fixture: claudecode config with 2 enabled + 1 disabled server, opencode
# config (JSONC) with 1 enabled + 1 disabled.
setup_project() {
  cat > "$WORK/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "chrome-devtools": { "type": "stdio", "command": ["npx", "chrome-devtools-mcp"], "enabled": true },
    "disabled-server": { "type": "stdio", "command": ["x"], "enabled": false },
    "unknown-tool": { "type": "stdio", "command": ["y"], "enabled": true }
  }
}
JSON
  cat > "$WORK/opencode.jsonc" <<'JSONC'
{
  // comment: JSONC must parse
  "mcp": {
    "qmd": { "type": "local", "command": ["qmd", "mcp"], "enabled": true },
    "disabled-oc": { "type": "local", "command": ["z"], "enabled": false }
  }
}
JSONC
}

@test "generates from live configs: union, sorted, enabled only" {
  setup_project

  run bash "$TOOL" "$WORK"
  assert_success

  run grep -c '^- \*\*' "$OUT"
  assert_equal "$output" "3" # chrome-devtools + qmd + unknown-tool; both disabled excluded

  run grep '^- \*\*qmd\*\*' "$OUT"
  assert_success
  run grep 'disabled-server\|disabled-oc' "$OUT"
  assert_failure
}

@test "known servers get curated guidance, unknown get fallback" {
  setup_project

  run bash "$TOOL" "$WORK"
  assert_success

  run grep '^- \*\*chrome-devtools\*\*: Use when you need to debug' "$OUT"
  assert_success
  run grep '^- \*\*unknown-tool\*\*: No guidance documented yet' "$OUT"
  assert_success
}

@test "idempotent: second run leaves the file unchanged" {
  setup_project

  run bash "$TOOL" "$WORK"
  assert_success
  local before
  before="$(cat "$OUT")"

  run bash "$TOOL" "$WORK"
  assert_success
  local after
  after="$(cat "$OUT")"
  assert_equal "$after" "$before"
}

@test "no harness configs: writes an explanatory note" {
  run bash "$TOOL" "$WORK"
  assert_success

  run cat "$OUT"
  assert_output --partial "(no MCP servers registered"
}
