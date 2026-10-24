#!/usr/bin/env bats
# =============================================================================
# src/agentic/git/tests/git_commits_skill_tests.bats
# Guards the skill's message gate: the checklist a message is measured
# against, the prose body named as a defect, and the only exemptions.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  SKILL="$MODULE_DIR/skills/git-commits/SKILL.md"
  # Prose wraps: grep each assertion against one flattened line.
  FLAT="$BATS_TEST_TMPDIR/skill-flat.md"
  tr '\n' ' ' < "$SKILL" | tr -s ' ' > "$FLAT"
}

@test "skill declares its frontmatter name" {
  run sed -n '1,4p' "$SKILL"
  assert_success
  assert_output --partial "name: devbot:git-commits"
}

@test "the checklist sits above the sections it explains" {
  local checklist subject body
  checklist="$(grep -n '^## Message checklist (MUST)' "$SKILL" | cut -d: -f1)"
  subject="$(grep -n '^## Subject' "$SKILL" | cut -d: -f1)"
  body="$(grep -n '^## Body' "$SKILL" | cut -d: -f1)"

  [ -n "${checklist}" ] && [ -n "${subject}" ] && [ -n "${body}" ]
  [ "${checklist}" -lt "${subject}" ]
  [ "${checklist}" -lt "${body}" ]
}

@test "the checklist covers subject, body and bullet shape" {
  local needle
  for needle in \
    'Subject: imperative, lowercase start, no trailing period, ≤72 characters.' \
    'Body: `Problems:` and `Solutions:`, each with at least one bullet.' \
    'Every bullet: one idea, ≤72 characters'; do
    run grep -qF "$needle" "$FLAT"
    assert_success
  done
}

@test "a paragraph body is a defect even when it explains the why" {
  # The failure this guards: a why-paragraph read as compliant because it does
  # not restate the diff. The prohibition is content-independent.
  run grep -qF 'No paragraph body — not even one explaining the why.' "$FLAT"
  assert_success
  run grep -qF 'any prose body is a defect, not a style choice' "$FLAT"
  assert_success
}

@test "the only exemptions are the messages git writes itself" {
  # `git revert` writes a body and `--fixup=amend:` copies the target message,
  # so the exemption covers the whole list — subject included, since git's
  # `Merge ...` subject is neither imperative nor lowercase.
  run grep -qF 'Exempt from this list: `Merge`/`Revert` as git writes them' "$FLAT"
  assert_success
  run grep -qF 'as `git commit --fixup`/`--squash` writes' "$FLAT"
  assert_success
  run grep -qF 'neither the subject rules nor the two-list form apply' "$FLAT"
  assert_success
  # A hand-typed marker must not be a way to skip the checklist.
  run grep -qF 'A marker prefix you type yourself is not an exemption.' "$FLAT"
  assert_success
}

@test "the checklist is the gate, and the detail below is not duplicated by it" {
  run grep -qF 'The sections below explain each rule in full; this list is the gate they exist to enforce.' "$FLAT"
  assert_success
  # Claiming otherwise while duplicating the rules is the drift create-skill warns about.
  run grep -qF 'it is not a summary of this skill' "$SKILL"
  assert_failure
}
