#!/usr/bin/env bats
# =============================================================================
# src/agentic/dev/tests/software-development_tests.bats
# Guards the skill's Workflows section: the selection order, the check-in
# mandate, and the two workflows it defines.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  SKILL="$MODULE_DIR/skills/software-development/SKILL.md"
  # Prose wraps: grep each assertion against one flattened line.
  FLAT="$BATS_TEST_TMPDIR/skill-flat.md"
  tr '\n' ' ' < "$SKILL" | tr -s ' ' > "$FLAT"
}

@test "skill declares its frontmatter name" {
  run sed -n '1,4p' "$SKILL"
  assert_success
  assert_output --partial "name: devbot:software-development"
}

@test "workflows section sits between When to Apply and the stack table" {
  local when workflows stack
  when="$(grep -n '^## When to Apply' "$SKILL" | cut -d: -f1)"
  workflows="$(grep -n '^## Workflows' "$SKILL" | cut -d: -f1)"
  stack="$(grep -n '^## Stack-Specific Instructions' "$SKILL" | cut -d: -f1)"

  [ -n "$when" ] && [ -n "$workflows" ] && [ -n "$stack" ]
  [ "$when" -lt "$workflows" ]
  [ "$workflows" -lt "$stack" ]
}

@test "workflows are selected by user, then configuration, then the default" {
  local user config default
  user="$(grep -nF '**Explicit user instruction**' "$SKILL" | cut -d: -f1)"
  config="$(grep -nF 'the `workflow` key in `.devbot.project.jsonc`' "$SKILL" | cut -d: -f1)"

  # The selection rule also honours a not-yet-migrated retired key.
  run grep -qF 'not-yet-migrated `worktrees` key' "$FLAT"
  assert_success

  run grep -qF '`true` → `worktrees`, `false` → `trunk`' "$FLAT"
  assert_success
  default="$(grep -nF 'the [Worktrees workflow](#worktrees-workflow) when no configuration names one' "$SKILL" | cut -d: -f1)"

  [ -n "$user" ] && [ -n "$config" ] && [ -n "$default" ]
  [ "$user" -lt "$config" ]
  [ "$config" -lt "$default" ]
}

@test "every step ends with a check-in, non-interactive runs excepted" {
  run grep -qF 'Check in after every step' "$FLAT"
  assert_success

  run grep -qF 'ask the user whether to continue or change something' "$FLAT"
  assert_success

  run grep -qF 'devbot:work-autonomously' "$FLAT"
  assert_success

  # A delegated subagent has no human to answer the check-in.
  run grep -qF 'a delegated subagent reports to its orchestrator' "$FLAT"
  assert_success
}

@test "the worktrees workflow is the first and the default" {
  local worktrees trunk
  worktrees="$(grep -n '^### Worktrees workflow' "$SKILL" | cut -d: -f1)"
  trunk="$(grep -n '^### Trunk workflow' "$SKILL" | cut -d: -f1)"

  [ -n "$worktrees" ] && [ -n "$trunk" ]
  [ "$worktrees" -lt "$trunk" ]

  run grep -qF 'The default. Each task gets its own branch in a linked worktree' "$FLAT"
  assert_success
}

@test "worktrees workflow carries a task to an open pull request without merging" {
  local needle
  for needle in \
    'worktree.sh create <branch>' \
    'when the assessment found the task already in a linked worktree' \
    'devbot:git-atomic-commits' \
    "the session's code reviewer" \
    'devbot:gh-create-pr' \
    'you never merge it'; do
    run grep -qF "$needle" "$FLAT"
    assert_success
  done
}

@test "trunk workflow works on the default branch with no pull request, stopping before the push" {
  local needle
  for needle in \
    'Work directly on the default branch' \
    'There are no pull requests' \
    'No branch, no worktree, no pull request' \
    'The user gates the push to `origin/<default>`' \
    'you never push the default branch yourself'; do
    run grep -qF "$needle" "$FLAT"
    assert_success
  done
}

@test "the review-loop mechanics stay in the command, not the always-loaded skill" {
  run grep -qF "cadence and reviewer-effort mechanics" "$FLAT"
  assert_success

  # The poll schedule belongs to devbot:work-autonomously.
  run grep -qF '60 checks' "$SKILL"
  assert_failure
}
