#!/usr/bin/env bats
# Tests for the auto-recover module (logic inlined in hook, no tool/install/update files).

setup() {
  load "$(npm root -g)/bats-support/load.bash"
  load "$(npm root -g)/bats-assert/load.bash"

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  HOOK_OPENCODE="$MODULE_DIR/hooks/opencode/on-session_error-auto-recover.ts"
  SKILL_FILE="$MODULE_DIR/skills/auto-recover/SKILL.md"
}

@test "opencode hook exists" { [ -f "$HOOK_OPENCODE" ]; }
@test "skill file exists" { [ -f "$SKILL_FILE" ]; }

@test "opencode hook exports OnSessionErrorAutoRecover plugin" {
  run grep -q 'OnSessionErrorAutoRecover' "$HOOK_OPENCODE"
  assert_success
}

@test "opencode hook uses Plugin type from opencode" {
  run grep -q '@opencode-ai/plugin' "$HOOK_OPENCODE"
  assert_success
}

@test "opencode hook has recovery logic inlined" {
  run grep -q 'TRANSIENT_RE' "$HOOK_OPENCODE"
  assert_success
  run grep -q 'RECOVERY_TEXT' "$HOOK_OPENCODE"
  assert_success
  run grep -q 'client.session.prompt' "$HOOK_OPENCODE"
  assert_success
}

@test "skill file has frontmatter" {
  run head -1 "$SKILL_FILE"
  assert_output --partial "---"
}

@test "skill file mentions session.error" {
  run grep -q 'session.error' "$SKILL_FILE"
  assert_success
}
