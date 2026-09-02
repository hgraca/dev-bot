#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/remove_mcp_key_tests.bats
# Tests for remove_mcp_key.py — removes an MCP server key from a JSONC config.
#
# audit-28 review F1: reset.sh removes module-managed MCP keys (devbot-tools,
# qmd) from opencode.jsonc before reinit re-registers them. This only works if
# the remover handles BOTH config shapes:
#   - opencode.jsonc: top-level "mcp" map        { "mcp": { "qmd": {...} } }
#   - .mcp.json (Claude Code): top-level "mcpServers" map
# The script previously handled only mcpServers, so opencode removals were
# silent no-ops (the stale qmd env from audit-28 kept crashing existing
# projects).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
  TOOL="${PROJECT_ROOT}/src/_shared/remove_mcp_key.py"

  WORK="$(mktemp -d)"
}

teardown() {
  rm -rf "$WORK" 2>/dev/null || true
}

_write_opencode_shape() {
  cat > "$WORK/opencode.jsonc" <<'JSONC_EOF'
{
  // opencode runtime config
  "mcp": {
    "devbot-tools": { "type": "local", "command": ["x"] },
    "qmd": { "type": "local", "command": ["qmd", "mcp"], "environment": { "QMD_LLAMA_GPU": true } }
  }
}
JSONC_EOF
}

_write_claude_shape() {
  cat > "$WORK/.mcp.json" <<'JSONC_EOF'
{
  "mcpServers": {
    "qmd": { "type": "stdio", "command": "qmd", "args": ["mcp"] }
  }
}
JSONC_EOF
}

@test "removes a key from the opencode.jsonc 'mcp' shape" {
  _write_opencode_shape

  run python3 "$TOOL" "$WORK/opencode.jsonc" "qmd"
  assert_success

  run python3 -c "
import json, sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/opencode.jsonc')
mcp = d.get('mcp', {})
assert 'qmd' not in mcp, mcp
assert 'devbot-tools' in mcp, mcp
print('OPCODE-REMOVE:OK')
"
  assert_success
  grep -qF 'OPCODE-REMOVE:OK' <<< "$output" || fail "qmd not removed from mcp map"
}

@test "removes a key from the .mcp.json 'mcpServers' shape (Claude Code)" {
  _write_claude_shape

  run python3 "$TOOL" "$WORK/.mcp.json" "qmd"
  assert_success

  run python3 -c "
import json
d = json.load(open('${WORK}/.mcp.json'))
servers = d.get('mcpServers', {})
assert 'qmd' not in servers, servers
print('CLAUDE-REMOVE:OK')
"
  assert_success
  grep -qF 'CLAUDE-REMOVE:OK' <<< "$output" || fail "qmd not removed from mcpServers"
}

@test "absent key is an idempotent no-op (exit 0, file unchanged content-wise)" {
  _write_opencode_shape
  local before
  before="$(cat "$WORK/opencode.jsonc")"

  run python3 "$TOOL" "$WORK/opencode.jsonc" "does-not-exist"
  assert_success

  assert_equal "$(cat "$WORK/opencode.jsonc")" "$before"
}

@test "missing file is an idempotent no-op (exit 0)" {
  run python3 "$TOOL" "$WORK/nope.jsonc" "qmd"
  assert_success
}
