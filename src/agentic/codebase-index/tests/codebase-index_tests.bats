#!/usr/bin/env bats
# =============================================================================
# src/agentic/codebase-index/tests/codebase-index_tests.bats
# Tests for the codebase-index module (MCP-based, no local tool).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  FIXTURES="$TEST_DIR/fixtures"
}

# ── Module structure ──────────────────────────────────────────────────────────

@test "opencode integration is the plugin (not a redundant MCP entry)" {
  # For opencode the package is integrated as a plugin, which itself spawns the
  # MCP server — registering it as an MCP too would double-load it.
  local plugin_config="$MODULE_DIR/plugin.opencode.json"
  [ -f "$plugin_config" ]
  run grep -q 'opencode-codebase-index' "$plugin_config"
  assert_success
  [ ! -f "$MODULE_DIR/mcp.opencode.json" ]
}

@test "claudecode MCP config registers codebase-index server" {
  local mcp_config="$MODULE_DIR/mcp.claudecode.json"
  [ -f "$mcp_config" ]
  run grep -q 'codebase-index-mcp' "$mcp_config"
  assert_success
}

@test "claudecode MCP launch routes through the EPIPE wrapper" {
  run grep -c 'node \.claude/codebase-index-mcp-wrapper\.js npx' \
    "$MODULE_DIR/mcp.claudecode.json"
  assert_equal "$output" "1"
}

@test "init.sh: symlinks the shared EPIPE wrapper into .claude" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  printf '{\n  "modules": { "claudecode": true, "opencode": false }\n}\n' \
    > "${tmpdir}/.devbot.project.jsonc"

  run bash "$MODULE_DIR/init.sh" "${tmpdir}"

  assert_success
  [[ -L "${tmpdir}/.claude/codebase-index-mcp-wrapper.js" ]]
  local shared_wrapper
  shared_wrapper="$(cd "$MODULE_DIR/../../.." && pwd)/src/_shared/mcp-stdio-wrapper.js"
  run readlink -f "${tmpdir}/.claude/codebase-index-mcp-wrapper.js"
  assert_output "${shared_wrapper}"

  rm -rf "${tmpdir}"
}

@test "install script exists" {
  [ -f "$MODULE_DIR/install.sh" ]
}

@test "init script exists" {
  [ -f "$MODULE_DIR/init.sh" ]
}

@test "skill file exists" {
  [ -f "$MODULE_DIR/skills/SKILL.md" ]
}

@test "skill file has frontmatter" {
  run head -1 "$MODULE_DIR/skills/SKILL.md"
  assert_output --partial "---"
}
