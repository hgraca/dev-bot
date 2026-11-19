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

@test "skill file defines the [WAITING_FOR_PTY] turn-ender marker" {
  run grep -q '\[WAITING_FOR_PTY\]' "$MODULE_DIR/skills/SKILL.md"
  assert_success
}

@test "the [WAITING_FOR_PTY] row states its precondition in both tables" {
  # The row is what a message-phrasing agent reads; pin it, not the prose.
  local skill="$MODULE_DIR/skills/SKILL.md"
  local profile="$MODULE_DIR/../devbot/agents/devbot.md"

  run grep -E '^\| *`\[WAITING_FOR_PTY\]`' "$skill"
  assert_success
  assert_output --partial 'wait you started'

  [ -f "$profile" ] || skip "the devbot profile is not installed here"
  run grep -E '^\| *`\[WAITING_FOR_PTY\]`' "$profile"
  assert_success
  assert_output --partial 'wait you started'

  # Both tables enumerate the same markers.
  local a b
  a="$(sed -nE 's/^\| *`\[([A-Z_]+)\]`.*/\1/p' "$skill")"
  b="$(sed -nE 's/^\| *`\[([A-Z_]+)\]`.*/\1/p' "$profile")"
  [ -n "$a" ]
  [ "$a" = "$b" ]
}

@test "both primary profiles require the wait to have started" {
  local rel path
  for rel in devbot/agents/devbot.md devteam/agents/teamlead.md; do
    path="$MODULE_DIR/../$rel"
    [ -f "$path" ] || continue
    run grep -q 'Confirm the wait actually started' "$path"
    assert_success
  done
}
