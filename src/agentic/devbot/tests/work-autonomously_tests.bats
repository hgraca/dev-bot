#!/usr/bin/env bats
# =============================================================================
# src/agentic/devbot/tests/work-autonomously_tests.bats
# Guards the work-autonomously command's contract: how the task argument is
# read, that half-finished work is resumed rather than restarted, and the
# Copilot review poll schedule.
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

@test "command assesses progress before changing anything" {
  grep -q 'Assess progress' "$FLAT"
  grep -q 'git log --oneline <default>..HEAD' "$FLAT"
  grep -q 'gh pr list --head' "$FLAT"
  grep -q 'git status --porcelain' "$FLAT"
}

@test "command resumes from the first incomplete step" {
  grep -qi 'No commits yet' "$FLAT"
  grep -qi 'Commits, and no pull request in any state' "$FLAT"
  grep -qi 'Pull request open' "$FLAT"
  grep -qi 'merged or closed' "$FLAT"
}

@test "command inspects every pull request state, so a closed one is not reopened" {
  grep -q -- '--state all' "$FLAT"
  grep -q 'mergedAt' "$FLAT"
  ! grep -q -- '--state open' "$FLAT"
}

@test "command never discards or duplicates work already done" {
  grep -qi 'never stash or discard' "$FLAT"
  grep -qi 'never reopen a closed pull request' "$FLAT"
  grep -qi 'never re-request Copilot while a review is still pending' "$FLAT"
}

@test "command polls Copilot every minute, 60 times" {
  grep -q '1 minute after each request before the first check' "$FLAT"
  grep -q 'maximum of 60 checks per request' "$FLAT"
  # The old cadence must be gone, not merely outnumbered by the new one.
  ! grep -q 'maximum of 12 checks' "$FLAT"
}
