#!/usr/bin/env bats
# =============================================================================
# src/agentic/guards/tests/guards_fixtures_tests.bats
# Guards engine behaviour driven by the static fixtures in test-fixtures/:
# first-match, stale-key tolerance, malformed/missing config fail-open, invalid
# regex skipped, and the global+project union.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIXTURES="${MODULE_DIR}/tests/test-fixtures"
  TOOL="${MODULE_DIR}/tools/guards.ts"
}

# _guard <command> <global-fixture> <project-fixture>
# Runs the engine against the named fixtures and captures output/status.
_guard() {
  local command="$1" global="$2" project="$3"
  local args=(--command "${command}")
  [[ -n "${global}" ]] && args+=(--global-config "${FIXTURES}/${global}")
  [[ -n "${project}" ]] && args+=(--project-config "${FIXTURES}/${project}")
  run bun "${TOOL}" "${args[@]}"
}

@test "first-match: the earlier rule's message wins within a config" {
  _guard "rm -rf /tmp/first-match" "" "guards-first-match.jsonc"
  assert_success
  assert_output --partial '"blocked":true'
  assert_output --partial 'Any rm blocked'
  refute_output --partial 'never reached'
}

# Rules carried an optional `agent` field, but neither harness ever supplied an
# agent name — opencode read an env var nothing set, claudecode hardcoded "" —
# so a scoped rule could never match. The field is gone; a config still carrying
# the stale key must keep working, with the rule applying to every caller. That
# is fail-closed: it blocks more than before, never less.
@test "a stale agent key on a rule is ignored, not fatal" {
  _guard "git push --force origin main" "" "guards-basic.jsonc"
  assert_success
  assert_output --partial '"blocked":true'
  assert_output --partial 'Force push not allowed from developer agent'
}

@test "malformed global config fails open (no rules loaded)" {
  _guard "rm -rf /tmp/x" "guards-global-malformed.jsonc" "guards-empty.jsonc"
  assert_success
  assert_output --partial '"blocked":false'
}

@test "malformed project config fails open" {
  _guard "rm -rf /tmp/x" "guards-global-empty.jsonc" "guards-malformed.jsonc"
  assert_success
  assert_output --partial '"blocked":false'
}

@test "a config without a guards key contributes no rules" {
  _guard "rm -rf /tmp/x" "guards-no-guards-key.jsonc" ""
  assert_success
  assert_output --partial '"blocked":false'
}

@test "an invalid regex rule is skipped, not fatal" {
  _guard "anything at all" "" "guards-invalid-regex.jsonc"
  assert_success
  assert_output --partial '"blocked":false'
}

@test "global and project rules both apply (union, each matches its own command)" {
  _guard "rm -rf /tmp/x" "guards-global-basic.jsonc" "guards-project-basic.jsonc"
  assert_output --partial '"blocked":true'
  assert_output --partial 'Dangerous recursive delete blocked (global)'

  _guard "docker system prune -f" "guards-global-basic.jsonc" "guards-project-basic.jsonc"
  assert_output --partial '"blocked":true'
  assert_output --partial 'Docker system prune blocked (project)'
}
