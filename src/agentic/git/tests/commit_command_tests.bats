#!/usr/bin/env bats
# =============================================================================
# src/agentic/git/tests/commit_command_tests.bats
# Guards the commit command's workflow contract: it commits where the selected
# workflow puts the work instead of always requiring a worktree.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  COMMAND="$MODULE_DIR/commands/commit.md"
  # Prose wraps: grep each assertion against one flattened line.
  FLAT="$BATS_TEST_TMPDIR/command-flat.md"
  tr '\n' ' ' < "$COMMAND" | tr -s ' ' > "$FLAT"
}

@test "commit command delegates workflow resolution to the worktree tool" {
  run grep -qF 'worktree.sh" enabled' "$FLAT"
  assert_success

  # The tool also honours a not-yet-migrated `worktrees` key.
  run grep -qF 'never read the config keys yourself' "$FLAT"
  assert_success
}

@test "commit command isolates first under the worktrees workflow" {
  run grep -qF '**exit `0`** — the `worktrees` workflow' "$FLAT"
  assert_success

  run grep -qF 'isolate the work first' "$FLAT"
  assert_success
}

@test "commit command commits on the default branch under the trunk workflow" {
  run grep -qF '**exit `1`** — the `trunk` workflow' "$FLAT"
  assert_success

  run grep -qF 'confirm the current checkout is on the default branch' "$FLAT"
  assert_success

  run grep -qF 'create no worktree and no branch' "$FLAT"
  assert_success
}

@test "commit command stops on an unknown workflow" {
  run grep -qF '**exit `2`** — the configured workflow is unknown' "$FLAT"
  assert_success
}
