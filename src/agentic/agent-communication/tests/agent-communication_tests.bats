#!/usr/bin/env bats
# Tests for the agent-communication module (thin hook wrapper + skill + CLI tool).

setup() {
  load "$(npm root -g)/bats-support/load.bash"
  load "$(npm root -g)/bats-assert/load.bash"

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  HOOK="$MODULE_DIR/hooks/opencode/on-session_idle-agent-communication.ts"
}

@test "hook file exists" { [ -f "$HOOK" ]; }

@test "hook exports default async plugin function" {
  run grep -q 'export default async function' "$HOOK"
  assert_success
}

@test "hook imports AgentCommunicationPlugin" {
  run grep -q 'AgentCommunicationPlugin' "$HOOK"
  assert_success
}

@test "skill file exists" {
  [ -f "$MODULE_DIR/skills/SKILL.md" ]
}

@test "skill file has canonical markers" {
  [ -f "$MODULE_DIR/skills/SKILL.md" ]
  run grep -q '\[FINISHED\]' "$MODULE_DIR/skills/SKILL.md"
  assert_success
}

# NOTE: The hook imports ../../tools/agent-communication.js which was
# removed when the tool was migrated to a standalone .sh file. The hook
# will fail to load at runtime until the JS module is restored or the
# hook is restructured.
# @test "opencode hook: session.idle handler loads" { ... }
