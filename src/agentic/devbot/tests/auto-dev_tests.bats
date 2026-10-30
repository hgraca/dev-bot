#!/usr/bin/env bats
# =============================================================================
# src/agentic/devbot/tests/auto-dev_tests.bats
# Guards the auto-dev command's contract: it refines a task with an
# open outcome once up front, follows whichever workflow is in use,
# skips the check-ins, and stops one step before the merge — while carrying
# the pull-request review loop's mechanics.
# =============================================================================

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  COMMAND="$MODULE_DIR/commands/auto-dev.md"
  # Prose wraps and is indented: grep each assertion against one flattened line.
  FLAT="$BATS_TEST_TMPDIR/command-flat.md"
  tr '\n' ' ' < "$COMMAND" | tr -s ' ' > "$FLAT"
}

@test "command frontmatter names devbot:auto-dev" {
  run sed -n '1,4p' "$COMMAND"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: devbot:auto-dev"* ]]
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

@test "command refines an underspecified task once, before any work" {
  # Ordering, not just existence: refinement has to be the step before the workflow.
  refine_line="$(grep -n '^2\. \*\*Refine' "$COMMAND" | cut -d: -f1)"
  workflow_line="$(grep -n '^3\. \*\*Load the workflow' "$COMMAND" | cut -d: -f1)"
  [ -n "$refine_line" ] && [ -n "$workflow_line" ]
  [ "$refine_line" -lt "$workflow_line" ]
  ! grep -q '^2\. \*\*Load the workflow' "$COMMAND"
}

@test "command gates the refinement on an open outcome" {
  grep -qi 'refine when the task leaves the outcome open' "$FLAT"
  grep -q 'more than one plausible reading of what to build' "$FLAT"
  grep -q 'no acceptance criteria derivable' "$FLAT"
  # A contract, architecture or migration change confirms the restate even with a spec.
  grep -q 'a public contract, the architecture or a data migration confirms the restate' "$FLAT"
}

@test "command skips the refinement when any skip condition holds" {
  grep -q 'Skip it when any of these holds' "$FLAT"
  grep -q 'resuming work already in progress' "$FLAT"
  grep -q 'the task is already a written spec' "$FLAT"
  grep -q 'one unambiguous, well-scoped change' "$FLAT"
}

@test "command refines through the grilling and interview-me skills" {
  grep -qi 'load the `grilling` and `interview-me`' "$FLAT"
  # grilling's round loop survives: rounds repeat until the frontier is empty.
  grep -q 'one batched round at a time until it is empty' "$FLAT"
  grep -q 'Outcome / User / Why now / Success / Constraint / Out of scope' "$FLAT"
  grep -q 'silence is not confirmation' "$FLAT"
  grep -q 'no human to answer, stop and report the blocker' "$FLAT"
  # The named exception: batched cadence and the non-interactive rule's scope.
  grep -q "takes \`grilling\`'s batched cadence" "$FLAT"
  grep -q 'covers the autonomous phase that follows, not this round' "$FLAT"
}

@test "refinement is the run's only planned pause" {
  grep -q "the run's only planned pause" "$FLAT"
  grep -q "this step is the run's DEFINE" "$FLAT"
  grep -q 'carried into the todo list when that list is created' "$FLAT"
  # The emergency stops survive: the check-in step defers to step 2 and adds its own.
  grep -q 'Stop only where step 2 or the workflow itself says to stop' "$FLAT"
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

@test "command's hand-back reports a pull request with its URL" {
  grep -q 'a pull request is always reported with its URL' "$FLAT"
  grep -q 'devbot:gh-create-pr' "$FLAT"
  # ...and never by a bare number.
  ! grep -qE '(PR|pull request) ?#[0-9]+' "$FLAT"
}

@test "command carries the pull-request review loop mechanics" {
  grep -q '@copilot' "$COMMAND"
  grep -q 'requestReviews' "$COMMAND"
  grep -q 'pull_request_review_id' "$COMMAND"
  grep -q '\*\*Review effort:\*\*' "$COMMAND"
}

@test "review loop verifies a request registered by reading the timeline" {
  # Stable signals only: event names, the scoped login and the baseline timestamp.
  grep -q 'review_requested' "$COMMAND"
  grep -q 'copilot_work_started' "$COMMAND"
  # Scoped to the bot, so a human reviewer's request cannot pass for Copilot's.
  grep -q 'requested_reviewer' "$COMMAND"
  grep -q 'issues/<pr>/timeline' "$COMMAND"
  # An event-id cursor, captured before the request: same-second timestamps
  # cannot reject a real request, and an older round's event cannot pass for it.
  grep -q 'since=' "$COMMAND"
  # --paginate runs --jq per page, so the per-page maxima are reduced here.
  grep -q -- '--paginate' "$COMMAND"
  grep -q 'sort -n' "$COMMAND"
  grep -q 'tail -1' "$COMMAND"
  cursor_line="$(grep -n 'since=' "$COMMAND" | cut -d: -f1 | head -1)"
  request_line="$(grep -n 'gh pr edit <pr> --add-reviewer' "$COMMAND" | cut -d: -f1 | head -1)"
  [ -n "$cursor_line" ] && [ -n "$request_line" ]
  [ "$cursor_line" -lt "$request_line" ]
}

@test "review loop falls back to the GraphQL request when nothing registered" {
  grep -q 'requestReviews' "$COMMAND"
  grep -q 'botIds' "$COMMAND"
  # The fallback must be executable: declared variables, bound by `gh api graphql`.
  grep -q 'gh api graphql' "$COMMAND"
  grep -q 'mutation($pr:ID!,$bot:ID!)' "$COMMAND"
  grep -q -- '-f bot=' "$COMMAND"
  # The fallback follows the timeline check, it does not replace it.
  timeline_line="$(grep -n 'issues/<pr>/timeline' "$COMMAND" | cut -d: -f1 | head -1)"
  fallback_line="$(grep -n 'requestReviews' "$COMMAND" | cut -d: -f1 | head -1)"
  [ -n "$timeline_line" ] && [ -n "$fallback_line" ]
  [ "$timeline_line" -lt "$fallback_line" ]
  # The baseline is re-captured before the mutation, so its own event still counts.
  recapture_line="$(grep -n 're-record' "$COMMAND" | cut -d: -f1 | head -1)"
  [ -n "$recapture_line" ]
  [ "$recapture_line" -lt "$fallback_line" ]
}

@test "review loop replies succinctly and resolves each thread" {
  grep -q 'one to three bullet points only' "$FLAT"
  grep -q 'each line at most 72 characters' "$FLAT"
  grep -q 'no prose' "$FLAT"
  grep -q 'then resolve the thread' "$FLAT"
  grep -q 'in the same format' "$FLAT"
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
