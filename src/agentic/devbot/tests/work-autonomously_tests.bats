#!/usr/bin/env bats
# =============================================================================
# src/agentic/devbot/tests/work-autonomously_tests.bats
# Guards the work-autonomously command's contract: it follows whichever
# workflow is in use, skips the check-ins, and stops one step before the
# merge — while carrying the pull-request review loop's mechanics.
# =============================================================================

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  COMMAND="$MODULE_DIR/commands/work-autonomously.md"
  # Prose wraps and is indented: grep each assertion against one flattened line.
  FLAT="$BATS_TEST_TMPDIR/command-flat.md"
  tr '\n' ' ' < "$COMMAND" | tr -s ' ' > "$FLAT"
}

@test "command frontmatter names devbot:work-autonomously" {
  run sed -n '1,4p' "$COMMAND"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: devbot:work-autonomously"* ]]
}

@test "command takes the whole argument, so a task can be given inline" {
  grep -q '\$ARGUMENTS' "$COMMAND"
  ! grep -q 'Task: \$1' "$COMMAND"
}

@test "command resolves a path, a URL and inline text as the task" {
  grep -qi 'file path is read' "$FLAT"
  grep -qi 'URL is' "$FLAT"
  grep -qi 'anything else is taken as the task' "$FLAT"
}

@test "no argument continues an assignment already in progress" {
  grep -q 'the assignment already in progress in this session' "$FLAT"
  grep -q 'continue it from where it stopped' "$FLAT"
  grep -q 'neither an argument nor an assignment in progress' "$FLAT"
  # Uncommitted work corroborates, it never defines the assignment.
  grep -q 'corroborate that the assignment is the same one' "$FLAT"
  grep -q 'never adopt or discard them' "$FLAT"
}

@test "command follows the workflow in use, never a hard-coded one" {
  grep -q 'Workflows section of `devbot:software-development`' "$FLAT"
  grep -q 'the workflow it selects for this run' "$FLAT"
  grep -q 'an explicit instruction in this command wins' "$FLAT"
  grep -q "the project's \`workflow\` configuration" "$FLAT"
  # A newer workflow must not require editing this command.
  ! grep -q 'Follow the `worktrees` workflow' "$FLAT"
  ! grep -q 'Follow the `trunk` workflow' "$FLAT"
}

@test "command skips the workflow's check-ins" {
  grep -q 'the workflow mandates a check-in after every step' "$FLAT"
  grep -q 'This run does not' "$FLAT"
  grep -q 'continue straight into the next one' "$FLAT"
}

@test "command resumes where the workflow's progress assessment sends it" {
  # The resume matrix lives in the skill now; the command inherits it.
  grep -q 'Follow the selected workflow' "$FLAT"
  ! grep -q 'Assess progress' "$FLAT"
  ! grep -q 'git status --porcelain' "$FLAT"
}

@test "command stops one step before the merge, for either workflow" {
  grep -q 'the stage just before merging to the default branch' "$FLAT"
  grep -q 'an open pull request whose review loop is clean' "$FLAT"
  grep -q 'the push still pending' "$FLAT"
  grep -q 'Never merge a pull request' "$FLAT"
  grep -q 'never push the default branch' "$FLAT"
}

@test "command carries the pull-request review loop mechanics" {
  grep -q '@copilot' "$COMMAND"
  grep -q 'requestReviews' "$COMMAND"
  grep -q 'pull_request_review_id' "$COMMAND"
  grep -q '\*\*Review effort:\*\*' "$COMMAND"
}

@test "command polls Copilot every minute, 60 times" {
  grep -q '1 minute after each request before the first check' "$FLAT"
  grep -q 'maximum of 60 checks per request' "$FLAT"
  # The old cadence must be gone, not merely outnumbered by the new one.
  ! grep -q 'maximum of 12 checks' "$FLAT"
}

@test "review loop is scoped to workflows that open a pull request" {
  grep -q '^## Review loop (when the workflow opens a pull request)' "$COMMAND"
}
