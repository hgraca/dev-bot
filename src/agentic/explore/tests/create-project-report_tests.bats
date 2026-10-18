#!/usr/bin/env bats
# =============================================================================
# src/agentic/explore/tests/create-project-report_tests.bats
# Wiring tests for the create-project-report skill's file references.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  SKILL="$MODULE_DIR/skills/create-project-report/SKILL.md"
}

@test "skill writes the project description to project.md" {
  run grep -q '\.agents/memory/active/project\.md' "$SKILL"
  assert_success
}

@test "skill no longer references a preemptive skill loading manifest" {
  run grep -qi 'preemptive' "$SKILL"
  assert_failure
}
