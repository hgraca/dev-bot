#!/usr/bin/env bats
# =============================================================================
# src/agentic/notion/tests/notion_context_tests.bats
# The scout's context-gathering use of Notion is instruction text, so these
# tests pin the contract each file must carry: the two-switch gate, the
# read-only search step, and the orchestrator's ask-to-enable behaviour.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
  NOTION_SKILL="${PROJECT_ROOT}/src/agentic/notion/skills/SKILL.md"
  GATHER="${PROJECT_ROOT}/src/agentic/explore/skills/gather-context/SKILL.md"
  SCOUT="${PROJECT_ROOT}/src/agentic/devteam/agents/scout.md"
  DEV_AGENT="${PROJECT_ROOT}/src/agentic/devbot/agents/devbot.md"
  TEAMLEAD="${PROJECT_ROOT}/src/agentic/devteam/agents/teamlead.md"
  DOCS="${PROJECT_ROOT}/src/agentic/notion/docs.md"
}

# ── Notion skill ─────────────────────────────────────────────────────────────

@test "notion skill carries the two-switch availability gate" {
  run grep -qF -- '--key mcps' "$NOTION_SKILL"
  assert_success
  run grep -qF -- '--key modules' "$NOTION_SKILL"
  assert_success
  run grep -qF 'Availability gate' "$NOTION_SKILL"
  assert_success
  run grep -qF 'enable the MCP before continuing' "$NOTION_SKILL"
  assert_success
  # A config is never flipped silently, and a declined offer skips the work.
  run grep -qF 'Never edit a config silently' "$NOTION_SKILL"
  assert_success
  run grep -qF 'On no, skip the Notion work' "$NOTION_SKILL"
  assert_success
}

# ── gather-context ───────────────────────────────────────────────────────────

@test "gather-context searches Notion read-only with the delegation keywords" {
  run grep -qF 'Search Notion for related context' "$GATHER"
  assert_success
  run grep -qF 'notion-search' "$GATHER"
  assert_success
  run grep -qF 'devbot:notion' "$GATHER"
  assert_success
  run grep -qF 'No matching Notion content' "$GATHER"
  assert_success
  run grep -qF '## Notion' "$GATHER"
  assert_success
  # Another enabled server must not stand in for the Notion entry.
  run grep -qF 'Another enabled server does' "$GATHER"
  assert_success
  # The lookup never mutates the workspace.
  run grep -qF 'never create, update, comment on, move or delete' "$GATHER"
  assert_success
  # A workspace-owned connection may omit notion-search: discover, then fall back.
  run grep -qF 'notion-get-tool-access' "$GATHER"
  assert_success
  run grep -qF 'call it alongside' "$GATHER"
  assert_success
  run grep -qF 'notion-connector-search' "$GATHER"
  assert_success
  # A legacy-only connection still has a callable search tool.
  run grep -qF 'notion-ai-search' "$GATHER"
  assert_success
  run grep -qF 'Notion search unavailable' "$GATHER"
  assert_success
  # The report contract names the skipped and unavailable outcomes.
  run grep -qF 'omit when the notion module is disabled' "$GATHER"
  assert_success
}

# ── Scout agent ──────────────────────────────────────────────────────────────

@test "scout names the Notion lookup alongside the Jira one" {
  run grep -qF 'devbot:notion' "$SCOUT"
  assert_success
  run grep -qF 'Search Notion' "$SCOUT"
  assert_success
}

# ── Orchestrators ────────────────────────────────────────────────────────────

@test "devbot: the session-start gate checks the Notion module and MCP" {
  run grep -qF 'Check the external context-source gates before delegating' "$DEV_AGENT"
  assert_success
  run grep -qiF 'notion' "$DEV_AGENT"
  assert_success
  run grep -qF -- '--key mcps' "$DEV_AGENT"
  assert_success
}

@test "teamlead: carries the Notion context-source gate" {
  run grep -qF 'Notion context source' "$TEAMLEAD"
  assert_success
  run grep -qF 'devbot:notion' "$TEAMLEAD"
  assert_success
}

@test "no agent still calls the shared gate the Jira gate" {
  run grep -qF 'after the Jira gate' "$DEV_AGENT"
  assert_failure
  run grep -qF 'after the Jira gate' "$TEAMLEAD"
  assert_failure
}

# ── Docs ─────────────────────────────────────────────────────────────────────

@test "docs document the scout context-gathering use" {
  run grep -qF 'gather-context' "$DOCS"
  assert_success
  # Docs must not hard-code a search tool the connection may not expose.
  run grep -qF 'notion-connector-search' "$DOCS"
  assert_success
  run grep -qF 'alongside' "$DOCS"
  assert_success
}
