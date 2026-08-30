#!/usr/bin/env bats
# Tests for the agent-communication module (CLI tool + skill).

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="$MODULE_DIR/tools/agent-communication.mcp.sh"
}

@test "tool exists" { [ -f "$TOOL" ]; }

@test "tool self-describes via mcp-meta" {
  run grep -q 'mcp-meta' "$TOOL"
  assert_success
}

@test "skill file exists" { [ -f "$MODULE_DIR/skills/SKILL.md" ]; }

@test "skill file has canonical markers" {
  run grep -q '\[FINISHED\]' "$MODULE_DIR/skills/SKILL.md"
  assert_success
}
