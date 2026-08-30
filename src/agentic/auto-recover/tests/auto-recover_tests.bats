#!/usr/bin/env bats
# Tests for the auto-recover module (logic in shared tool, thin harness hooks).

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  DEV_BOT_ROOT="$(cd "$MODULE_DIR/../.." && pwd)"
  HOOK_OPENCODE="$MODULE_DIR/hooks/opencode/on-session_error-auto-recover.ts"
  TOOL="$MODULE_DIR/tools/auto-recover.ts"
  SKILL_FILE="$MODULE_DIR/skills/auto-recover/SKILL.md"
}

@test "opencode hook exists" { [ -f "$HOOK_OPENCODE" ]; }
@test "skill file exists" { [ -f "$SKILL_FILE" ]; }
@test "shared auto-recover tool exists" { [ -f "$TOOL" ]; }

@test "opencode hook exports OnSessionErrorAutoRecover plugin" {
  run grep -q 'OnSessionErrorAutoRecover' "$HOOK_OPENCODE"
  assert_success
}

@test "opencode hook uses Plugin type from opencode" {
  run grep -q '@opencode-ai/plugin' "$HOOK_OPENCODE"
  assert_success
}

@test "opencode hook delegates to shared tool and injects prompt" {
  run grep -q 'tools/auto-recover.ts' "$HOOK_OPENCODE"
  assert_success
  run grep -q 'client.session.prompt' "$HOOK_OPENCODE"
  assert_success
}

@test "shared tool holds the recovery logic" {
  run grep -q 'TRANSIENT_RE' "$TOOL"
  assert_success
  run grep -q 'RECOVERY_TEXT' "$TOOL"
  assert_success
  run grep -q 'checkAndAcquire' "$TOOL"
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
