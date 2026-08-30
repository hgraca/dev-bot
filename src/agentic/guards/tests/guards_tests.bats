#!/usr/bin/env bats
# =============================================================================
# src/agentic/guards/tests/guards_tests.bats
# Tests for the guards module (manifest-declared hook + shared tool).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  MANIFEST="$MODULE_DIR/hooks.json"
  TOOL="$MODULE_DIR/tools/guards.ts"
  SKILL_FILE="$MODULE_DIR/skills/SKILL.md"
}

@test "hooks.json declares a blocking command.before guard hook" {
  run python3 -c "
import json
data = json.load(open('${MANIFEST}'))
hook = data['hooks'][0]
assert hook['event'] == 'command.before', hook
assert hook['blocking'] is True, hook
assert 'guards.ts' in hook['run'][1], hook
print('MANIFEST:OK')
"
  assert_success
  grep -qF 'MANIFEST:OK' <<< "$output" || fail "manifest missing or malformed"
}

@test "shared guards tool exists" { [ -f "$TOOL" ]; }
@test "skill file exists" { [ -f "$SKILL_FILE" ]; }

@test "skill file has frontmatter" {
  run head -1 "$SKILL_FILE"
  assert_output --partial "---"
}

# ── Matching semantics (anchored per command segment) ──────────────────────────

@test "guards block a direct dangerous invocation" {
  run bun run "$TOOL" --command "rm -rf /tmp/guards-direct" --global-config "$TEST_DIR/../../../../.devbot.global.jsonc" --project-config "$TEST_DIR/../../../../tests/test-project/.devbot.project.jsonc" --agent ""
  assert_output --partial '"blocked":true'
}

@test "guards do NOT block a safe command whose TEXT contains the pattern" {
  run bun run "$TOOL" --command 'echo "rm -rf is just text here"' --global-config "$TEST_DIR/../../../../.devbot.global.jsonc" --project-config "$TEST_DIR/../../../../tests/test-project/.devbot.project.jsonc" --agent ""
  assert_output --partial '"blocked":false'
}

@test "guards still block the pattern after a shell operator" {
  run bun run "$TOOL" --command "echo hi && rm -rf /tmp/guards-op" --global-config "$TEST_DIR/../../../../.devbot.global.jsonc" --project-config "$TEST_DIR/../../../../tests/test-project/.devbot.project.jsonc" --agent ""
  assert_output --partial '"blocked":true'
}

@test "guards still block a command-runner wrapping the pattern" {
  run bun run "$TOOL" --command 'bash -c "rm -rf /tmp/guards-wrap"' --global-config "$TEST_DIR/../../../../.devbot.global.jsonc" --project-config "$TEST_DIR/../../../../tests/test-project/.devbot.project.jsonc" --agent ""
  assert_output --partial '"blocked":true'
}

@test "guards still block command substitution containing the pattern" {
  run bun run "$TOOL" --command 'echo \$(rm -rf /tmp/guards-sub)' --global-config "$TEST_DIR/../../../../.devbot.global.jsonc" --project-config "$TEST_DIR/../../../../tests/test-project/.devbot.project.jsonc" --agent ""
  assert_output --partial '"blocked":true'
}
