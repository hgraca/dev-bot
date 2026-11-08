#!/usr/bin/env bats
# =============================================================================
# src/agentic/atlassian/tests/jira_lifecycle_tests.bats
# The Jira workflow is instruction text, so these tests pin the contract each
# agent file and skill must carry: a ticket is only useful if the session
# bootstrap actually consults it, in the right order.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"

  DEV_AGENT="${PROJECT_ROOT}/src/agentic/devbot/agents/devbot.md"
  TEAMLEAD="${PROJECT_ROOT}/src/agentic/devteam/agents/teamlead.md"
  AUTO_DEV="${PROJECT_ROOT}/src/agentic/devbot/commands/auto-dev.md"
  FINISH_FLOW="${PROJECT_ROOT}/src/agentic/agent-communication/skills/SKILL.md"
}

line_of() {
  # First line number containing the fixed string, or empty.
  grep -nF "$2" "$1" | head -1 | cut -d: -f1
}

@test "devbot: the Jira gate runs before the scout delegation, resolution after it" {
  local gate scout resolve
  gate="$(line_of "$DEV_AGENT" 'Check the external context-source gates before delegating')"
  scout="$(line_of "$DEV_AGENT" 'Delegate to @scout to gather context')"
  resolve="$(line_of "$DEV_AGENT" 'Resolve the Jira ticket')"

  [ -n "$gate" ] && [ -n "$scout" ] && [ -n "$resolve" ]
  [ "$gate" -lt "$scout" ]
  [ "$scout" -lt "$resolve" ]
}

@test "devbot: the gate consults the configured server state, not a guess" {
  run grep -qF -- '--key mcps' "$DEV_AGENT"
  assert_success
  run grep -qF -- '--session-root' "$DEV_AGENT"
  assert_success
  run grep -qF 'atlassian' "$DEV_AGENT"
  assert_success
}

@test "devbot: a resumed DOING ticket is never moved back to TODO" {
  run grep -qF 'leave an actionable or in-progress ticket untouched' "$DEV_AGENT"
  assert_success
  run grep -qF 'leave an actionable or in-progress ticket untouched' "$TEAMLEAD"
  assert_success
}

@test "devbot: names both Jira skills and the ticket statuses" {
  for needle in 'devbot:jira-workflow' 'devbot:create-jira-issue' 'DOING' 'CANCELED'; do
    run grep -qF "$needle" "$DEV_AGENT"
    assert_success
  done
}

@test "devbot: opens the ticket at the BUILD gate and closes it on both finish paths" {
  run grep -qF 'Open the Jira ticket before BUILD' "$DEV_AGENT"
  assert_success
  # The follow-up-prompt finish flow and the assignment-end finish flow.
  run grep -qF '`devbot:jira-workflow`: DONE once the work has landed' "$DEV_AGENT"
  assert_success
  run grep -qF 'the commit on the default branch under the trunk workflow' "$DEV_AGENT"
  assert_success
}

@test "teamlead: carries the ticket gate, the skill triggers and the close" {
  for needle in \
    'devbot:jira-workflow' \
    'devbot:create-jira-issue' \
    'Jira ticket resolved before planning' \
    'close the Jira ticket with `devbot:jira-workflow`'; do
    run grep -qF "$needle" "$TEAMLEAD"
    assert_success
  done
}

@test "auto-dev: resolves the ticket inside its one pause and opens it entering BUILD" {
  run grep -qF 'devbot:jira-workflow' "$AUTO_DEV"
  assert_success
  run grep -qF 'Every Jira decision' "$AUTO_DEV"
  assert_success
  # No @scout in this run, so the lookup has to be its own.
  run grep -qF 'JQL lookup yourself' "$AUTO_DEV"
  assert_success
  run grep -qF 'pre-implementation step' "$AUTO_DEV"
  assert_success
  run grep -qF 'DOING' "$AUTO_DEV"
  assert_success
}

@test "agent-communication: the canonical finish flow names the ticket close" {
  run grep -qF 'close the session'"'"'s Jira ticket with `devbot:jira-workflow`' "$FINISH_FLOW"
  assert_success
}

@test "scout: searches Jira read-only when the MCP is enabled" {
  local scout="${PROJECT_ROOT}/src/agentic/devteam/agents/scout.md"

  run grep -qF 'devbot:atlassian' "$scout"
  assert_success
  run grep -qiF 'read-only' "$scout"
  assert_success
  run grep -qiF 'transition a Jira issue' "$scout"
  assert_success
}

@test "gather-context: pins both switches, the JQL rule and the report section" {
  local skill="${PROJECT_ROOT}/src/agentic/explore/skills/gather-context/SKILL.md"

  run grep -qF -- '--key mcps' "$skill"
  assert_success
  run grep -qF -- '--key modules' "$skill"
  assert_success
  run grep -qF 'JQL' "$skill"
  assert_success
  run grep -qF 'No matching Jira ticket' "$skill"
  assert_success
  run grep -qF '## Jira ticket' "$skill"
  assert_success
  # Another enabled server must not stand in for the Atlassian entry.
  run grep -qF 'another enabled server does' "$skill"
  assert_success
}

@test "gh-create-pr: a resolved ticket makes the title prefix mandatory" {
  local skill="${PROJECT_ROOT}/src/agentic/github/skills/gh-create-pr/SKILL.md"
  local command="${PROJECT_ROOT}/src/agentic/github/commands/gh-create-pr.md"

  run grep -qF 'the title **must** start with its key' "$skill"
  assert_success
  run grep -qF 'Jira links the pull' "$skill"
  assert_success
  run grep -qF '`devbot:jira-workflow`' "$skill"
  assert_success
  run grep -qF 'prefixed with its key' "$command"
  assert_success
}
