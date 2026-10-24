#!/usr/bin/env bats
# =============================================================================
# src/agentic/self-improvement/tests/create_skill_tests.bats
# Guards the rule about referencing another skill: name it and require it, never
# restate it — a summary lets the reader believe it has read the rule.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  SKILL="$MODULE_DIR/skills/create-skill/SKILL.md"
  # Prose wraps: grep each assertion against one flattened line.
  FLAT="$BATS_TEST_TMPDIR/skill-flat.md"
  tr '\n' ' ' < "$SKILL" | tr -s ' ' > "$FLAT"
}

@test "skill declares its frontmatter name" {
  run sed -n '1,4p' "$SKILL"
  assert_success
  assert_output --partial "name: devbot:create-skill"
}

@test "referencing another skill has its own section, after file references" {
  local refs sub_rule
  refs="$(grep -n '^#### File References' "$SKILL" | cut -d: -f1)"
  sub_rule="$(grep -n '^#### Referencing another skill' "$SKILL" | cut -d: -f1)"

  [ -n "${refs}" ] && [ -n "${sub_rule}" ]
  [ "${refs}" -lt "${sub_rule}" ]
}

@test "restating enough that the reference can be skipped is forbidden" {
  run grep -qF 'Do not restate enough of it that the reference can be skipped' "$FLAT"
  assert_success
  run grep -qF 'name the skill, say when to load it, and point at it for the rules' "$FLAT"
  assert_success
}

@test "the example is generic, not coupled to one skill's wording" {
  run grep -qF 'devbot:some-skill' "$FLAT"
  assert_success
  run grep -qF 'devbot:git-commits' "$FLAT"
  assert_failure
}

@test "the skill says why a restatement is worse than silence" {
  run grep -qF 'Restating is worse than silence.' "$FLAT"
  assert_success
  run grep -qF 'believes it has read the rule' "$FLAT"
  assert_success
  run grep -qF 'the two copies drift' "$FLAT"
  assert_success
}

@test "the summarising skill may not read as self-sufficient" {
  run grep -qF 'never let the summarising skill read as self-sufficient' "$FLAT"
  assert_success
  run grep -qF 'the rule lives in the skill you named' "$FLAT"
  assert_success
}

@test "existing restatements are follow-up, not a licence" {
  run grep -qF 'Existing skills that still restate a referenced rule are follow-up work' "$FLAT"
  assert_success
  run grep -qF 'not a licence to add more' "$FLAT"
  assert_success
}
