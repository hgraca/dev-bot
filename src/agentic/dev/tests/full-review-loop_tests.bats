#!/usr/bin/env bats
# =============================================================================
# src/agentic/dev/tests/full-review-loop_tests.bats
# Guards the full-review-loop command: local loop, pull request, host review,
# squash, merge handover — GitHub Copilot named as the shipped example, not a
# requirement, because the git host may be another one.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  COMMAND="$MODULE_DIR/commands/full-review-loop.md"
  # Prose wraps: grep each assertion against one flattened line.
  FLAT="$BATS_TEST_TMPDIR/command-flat.md"
  tr '\n' ' ' < "$COMMAND" | tr -s ' ' > "$FLAT"
}

@test "command declares its frontmatter name" {
  run sed -n '1,4p' "$COMMAND"
  assert_success
  assert_output --partial "name: devbot:full-review-loop"
}

@test "command chains the generic loop with both adapters" {
  local needle
  for needle in 'devbot:review-loop' 'devbot:gh-create-pr' 'devbot:gh-review-loop' '`@reviewer`'; do
    run grep -qF "$needle" "$FLAT"
    assert_success
  done
}

@test "GitHub Copilot is the shipped example, not a requirement" {
  run grep -q 'shipped adapters' "$FLAT"
  assert_success
  run grep -qiE 'gitlab|bitbucket' "$FLAT"
  assert_success
  run grep -q 'Never invent' "$FLAT"
  assert_success
}

@test "the local loop and its squash come before the pull request" {
  local local_line squash_line request_line remote_line handback_line
  local_line="$(grep -n 'Local loop' "$COMMAND" | cut -d: -f1 | head -1)"
  squash_line="$(grep -n '\*\*Squash\*\*' "$COMMAND" | cut -d: -f1 | head -1)"
  request_line="$(grep -n '\*\*Pull request\*\*' "$COMMAND" | cut -d: -f1 | head -1)"
  remote_line="$(grep -n 'Remote loop' "$COMMAND" | cut -d: -f1 | head -1)"
  handback_line="$(grep -n 'Hand back' "$COMMAND" | cut -d: -f1 | head -1)"

  [ -n "$local_line" ] && [ -n "$squash_line" ] && [ -n "$request_line" ]
  [ -n "$remote_line" ] && [ -n "$handback_line" ]
  [ "$local_line" -lt "$squash_line" ]
  [ "$squash_line" -lt "$request_line" ]
  [ "$request_line" -lt "$remote_line" ]
  [ "$remote_line" -lt "$handback_line" ]
}

@test "it ends with the force-push handover and never merges" {
  run grep -q 'push --force-with-lease' "$FLAT"
  assert_success
  run grep -q 'force-pushes and merges' "$FLAT"
  assert_success
  run grep -q 'Do not merge' "$FLAT"
  assert_success
}

@test "both loop steps stop before the skill's own Finish" {
  # The command owns the two squashes; a step that lets review-loop finish
  # squashes and hands over a second time.
  run grep -o 'stop before its Finish' "$FLAT"
  assert_success
  [ "${#lines[@]}" -eq 2 ]
}

@test "the pull request step keeps gh-create-pr's inputs" {
  run grep -q 'still show the plan' "$FLAT"
  assert_success
  run grep -q 'never skip a required field' "$FLAT"
  assert_success
}

@test "the fixup-push prohibition is scoped to the local loop" {
  # A blanket ban would stop the remote loop converging: the reviewer sees
  # only pushed commits, so its fixups must be pushed and squashed at the end.
  run grep -q "Do not push the local loop's" "$FLAT"
  assert_success
  run grep -q 'The remote loop does push its fixups' "$FLAT"
  assert_success
}

@test "no exclamation mark sits directly before a backtick" {
  # The harness runs !`cmd` inline in a command file, so a code span
  # ending in "fixup!" executed the prose after it as shell.
  run grep -nF '!`' "$COMMAND"
  assert_failure 1
}
