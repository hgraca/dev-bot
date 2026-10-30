#!/usr/bin/env bats
# =============================================================================
# src/agentic/dev/tests/address-review_tests.bats
# Guards the skill's local-only rule and the Copilot loop's one exception:
# a succinct resolution reply, then the thread marked resolved.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  SKILL="$MODULE_DIR/skills/address-review/SKILL.md"
  # Prose wraps: grep each assertion against one flattened line.
  FLAT="$BATS_TEST_TMPDIR/skill-flat.md"
  tr '\n' ' ' < "$SKILL" | tr -s ' ' > "$FLAT"
}

@test "skill declares its frontmatter name" {
  run sed -n '1,4p' "$SKILL"
  assert_success
  assert_output --partial "name: devbot:address-review"
}

@test "skill stays local-only outside the Copilot loop" {
  run grep -q 'Keep all actions local' "$FLAT"
  assert_success
  run grep -q 'never post replies, comments, or resolutions back to the review source' "$FLAT"
  assert_success
  run grep -q 'except in the Copilot loop in `devbot:auto-dev`' "$FLAT"
  assert_success
}

@test "Copilot loop replies succinctly and resolves each thread" {
  # The scope prefix keeps the format from licensing posting in general.
  run grep -q 'In that Copilot loop, reply to each finding' "$FLAT"
  assert_success
  run grep -q 'one to three bullet points only' "$FLAT"
  assert_success
  run grep -q 'each line at most 72 characters' "$FLAT"
  assert_success
  run grep -q 'no prose' "$FLAT"
  assert_success
  run grep -q 'mark its thread resolved' "$FLAT"
  assert_success
  # A review-body-only finding has no thread to resolve.
  run grep -q 'has no thread' "$FLAT"
  assert_success
}
