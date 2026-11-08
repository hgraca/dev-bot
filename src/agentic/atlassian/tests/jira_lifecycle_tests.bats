#!/usr/bin/env bats

# =============================================================================

# src/agentic/atlassian/tests/jira_lifecycle_tests.bats

# The Jira workflow is instruction text, so these tests pin the contract each

# agent file and skill must carry: the tickets are only useful if the session

# bootstrap actually consults them, in the right order.

# =============================================================================

setup() {
bats_load_library bats-support
bats_load_library bats-assert

TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"

DEV_AGENT="${PROJECT_ROOT}/src/agentic/devbot/agents/devbot.md"
  TEAMLEAD="${PROJECT_ROOT}/src/agentic/devteam/agents/teamlead.md"
AUTO_DEV="${PROJECT_ROOT}/src/agentic/devbot/commands/auto-dev.md"
}

line_of() {

# First line number containing the fixed string, or empty.

grep -nF "$2" "$1" | head -1 | cut -d: -f1
}

@test "devbot: the Jira gate runs before the scout delegation, resolution after it" {
local gate scout resolve
gate="$(line_of "$DEV_AGENT" 'Check the Jira gate before delegating')"
scout="$(line_of "$DEV_AGENT" 'Delegate to @scout to gather context')"
resolve="$(line_of "$DEV_AGENT" 'Resolve the Jira ticket')"

[ -n "$gate" ] && [ -n "$scout" ] && [ -n "$resolve" ]
  [ "$gate" -lt "$scout" ]
  [ "$scout" -lt "$resolve" ]
}

@test "devbot: the gate consults the live server state, not a guess" {
run grep -qF -- '--key mcps' "$DEV_AGENT"
  assert_success
  run grep -qF 'atlassian' "$DEV_AGENT"
assert_success
}

@test "devbot: names both Jira skills and the ticket statuses" {
for needle in 'devbot:jira-workflow' 'devbot:create-jira-issue' 'DOING' 'CANCELED'; do
run grep -qF "$needle" "$DEV_AGENT"
assert_success
done
}

@test "devbot: opens the ticket at the BUILD gate and closes it in the finish flow" {
run grep -qF 'Open the Jira ticket before BUILD' "$DEV_AGENT"
  assert_success
  run grep -qF 'close the Jira ticket with `devbot:jira-workflow`' "$DEV_AGENT"
assert_success

# Both finish-flow statements carry the close, so neither path can drop it.

assert_equal "$(grep -cF 'CANCELED' "$DEV_AGENT")" "2"
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
  run grep -qF 'inside this' "$AUTO_DEV"
assert_success
run grep -qF "pre-implementation step" "$AUTO_DEV"
  assert_success
  run grep -qF 'DOING' "$AUTO_DEV"
assert_success
}
