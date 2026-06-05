#!/usr/bin/env bats
# =============================================================================
# src/agentic/guards/tests/guards_tests.bats
# Tests for the guards module (hook-based, no standalone tool).
# =============================================================================

setup() {
  load "$(npm root -g)/bats-support/load.bash"
  load "$(npm root -g)/bats-assert/load.bash"

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  HOOK_OPENCODE="$MODULE_DIR/hooks/opencode/on-tool_execute_before-guards.ts"
  HOOK_CLAUDECODE="$MODULE_DIR/hooks/claudecode/on_tool_execute_before-guards.sh"
  SKILL_FILE="$MODULE_DIR/skills/SKILL.md"
}

@test "opencode hook exists" {
  [ -f "$HOOK_OPENCODE" ]
}

@test "opencode hook exports GuardsPlugin" {
  run grep -q 'GuardsPlugin' "$HOOK_OPENCODE"
  assert_success
}

@test "opencode hook imports from @opencode-ai/plugin" {
  run grep -q '@opencode-ai/plugin' "$HOOK_OPENCODE"
  assert_success
}

@test "opencode hook has guard evaluation logic" {
  run grep -q 'guard' "$HOOK_OPENCODE"
  assert_success
}

@test "claudecode hook exists" {
  [ -f "$HOOK_CLAUDECODE" ]
}

@test "claudecode hook is executable" {
  [ -x "$HOOK_CLAUDECODE" ]
}

@test "skill file exists" {
  [ -f "$SKILL_FILE" ]
}

@test "skill file has frontmatter" {
  run head -1 "$SKILL_FILE"
  assert_output --partial "---"
}
