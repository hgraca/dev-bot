#!/usr/bin/env bats
# =============================================================================
# src/agentic/explore/tests/create-project-report_tests.bats
# Wiring tests for the create-project-report skill's file references.
#
# audit-21 FAIL: the skill said the preemptive manifest is
# 'preemptive-skill-loading.md' while the real file — scaffolded by the memory
# template, referenced by session-start instructions — is
# 'preemptive-skill-loading-list.md'. An agent following the skill would have
# written a second, differently-named file and never updated the real one.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  SKILL="$MODULE_DIR/skills/create-project-report/SKILL.md"
}

@test "skill references the real preemptive-skill-loading-list.md filename" {
  run grep -q 'preemptive-skill-loading-list\.md' "$SKILL"
  assert_success

  # The wrong (suffix-less) name must not appear anywhere.
  run grep -q 'preemptive-skill-loading\.md' "$SKILL"
  assert_failure
}
