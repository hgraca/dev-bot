#!/usr/bin/env bats
# =============================================================================
# src/agentic/dev/tests/review-loop_tests.bats
# Guards the reviewer-agnostic loop's contract: the policy lives here, and the
# reviewer's mechanics stay in its adapter (devbot:gh-review-loop for Copilot).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  SKILL="$MODULE_DIR/skills/review-loop/SKILL.md"
  # Prose wraps: grep each assertion against one flattened line.
  FLAT="$BATS_TEST_TMPDIR/skill-flat.md"
  tr '\n' ' ' < "$SKILL" | tr -s ' ' > "$FLAT"
}

@test "skill declares its frontmatter name" {
  run sed -n '1,4p' "$SKILL"
  assert_success
  assert_output --partial "name: devbot:review-loop"
}

@test "skill is reviewer-agnostic: both adapters named, no host mechanics" {
  run grep -q 'Local' "$FLAT"
  assert_success
  run grep -q 'Remote' "$FLAT"
  assert_success
  run grep -q '`@reviewer`' "$FLAT"
  assert_success
  # Copilot and GitHub are the shipped example, never the loop itself.
  run grep -q 'requestReviews' "$SKILL"
  assert_failure
  run grep -q 'pr-watch' "$SKILL"
  assert_failure
  run grep -q 'gh pr checks' "$SKILL"
  assert_failure
  # Any host command is a leak, not only the ones named above.
  run grep -qE '(^|[^[:alnum:]-])gh (api|pr|repo|auth)' "$SKILL"
  assert_failure
  run grep -q 'GitHub' "$SKILL"
  assert_failure
}

@test "the local adapter delegates to a code reviewer and posts nothing" {
  run grep -q 'delegate' "$FLAT"
  assert_success
  run grep -q 'nothing is posted' "$FLAT"
  assert_success
  run grep -q 'devbot:address-review' "$FLAT"
  assert_success
  # The interactive-gated agent is not the only local reviewer.
  run grep -q '`@code-reviewer`' "$FLAT"
  assert_success
}

@test "every finding is a fixup and gets an answer, false positive included" {
  run grep -q 'one commit per finding' "$FLAT"
  assert_success
  run grep -q 'false positive' "$FLAT"
  assert_success
  run grep -q 'never silence' "$FLAT"
  assert_success
  # A remote round pushes before re-requesting, or the reviewer sees the old tip.
  run grep -q 'push the fixups' "$FLAT"
  assert_success
}

@test "convergence is a round, not an empty thread list" {
  run grep -q 'no new findings' "$FLAT"
  assert_success
  run grep -q 'thread list' "$FLAT"
  assert_success
}

@test "the gate runs before the history is touched" {
  run grep -q 'Gate before the history is touched' "$FLAT"
  assert_success
  # The local half has its own gate step, defined in terms of real checks.
  run grep -q '^### Gate' "$SKILL"
  assert_success
  run grep -q 'make lint' "$FLAT"
  assert_success
}

@test "finish squashes and branches on pre-push or post-push" {
  run grep -q 'Squash the fixups' "$FLAT"
  assert_success
  run grep -q 'Pre-push' "$FLAT"
  assert_success
  run grep -q 'Post-push' "$FLAT"
  assert_success
  run grep -q 'Never merge' "$FLAT"
  assert_success
  # The lease command belongs to the post-push branch, never the pre-push one.
  run grep -qE 'Post-push.*push --force-with-lease' "$FLAT"
  assert_success
  # A polyrepo session runs the push from a directory that has an origin.
  run grep -q 'git -C <owner> push' "$FLAT"
  assert_success
}
