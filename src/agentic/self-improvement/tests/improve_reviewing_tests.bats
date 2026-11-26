#!/usr/bin/env bats
# =============================================================================
# src/agentic/self-improvement/tests/improve_reviewing_tests.bats
# Guards the rules the improve-reviewing skill owns: the final consistency pass
# over the changed files before publishing, unattended publishing in the finish
# flow, and the one canonical pull request every session appends to instead of
# opening a second.
# Assertions are scoped to the step that carries each rule, so a reworded-but-
# correct file passes and a rule deleted or weakened fails.
# =============================================================================

# Body of a `### <heading>` step, up to the next heading, flattened to one line.
step_flat() {
  awk -v h="### $2" '
    $0 == h            { on = 1; next }
    on && /^##/        { exit }
    on                 { print }
  ' "$1" | tr '\n' ' ' | tr -s ' '
}

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  SKILL="$MODULE_DIR/skills/improve-reviewing/SKILL.md"

  PASS="$(step_flat "$SKILL" '5. Final pass over the changed files')"
  PUBLISH="$(step_flat "$SKILL" '6. Publish the pull request')"
  SETUP="$(step_flat "$SKILL" '3. Assess progress before cutting anything')"
  REPORT="$(step_flat "$SKILL" '7. Report')"
}

@test "skill carries a final pass step before publishing" {
  [ -n "$PASS" ]
  [ -n "$PUBLISH" ]
  # The pass must come first, or it cannot clean what it publishes.
  local pass_line publish_line
  pass_line="$(grep -n '^### 5\. Final pass over the changed files' "$SKILL" | cut -d: -f1)"
  publish_line="$(grep -n '^### 6\. Publish the pull request' "$SKILL" | cut -d: -f1)"
  [ "${pass_line:-0}" -lt "${publish_line:-0}" ]
}

@test "final pass names every defect class it removes" {
  printf '%s\n' "$PASS" | grep -qi 'inconsisten'
  printf '%s\n' "$PASS" | grep -qi 'redundan'
  printf '%s\n' "$PASS" | grep -qi 'duplicat'
  printf '%s\n' "$PASS" | grep -qi 'ambiguit'
}

@test "final pass re-reads every touched file and renumbers what it merges" {
  printf '%s\n' "$PASS" | grep -qiF 'every file the change touched'
  printf '%s\n' "$PASS" | grep -qiF 'Renumber'
  # Tidying must never drop a check.
  printf '%s\n' "$PASS" | grep -qF 'Keep every property'
}

@test "the pull request title is fixed, not composed from the gaps" {
  # The literal also appears in the title lookup, so pin the specification itself.
  grep -A3 '^The title is fixed:' "$SKILL" | grep -qF 'chore(improve-reviews): improve review skill'
  printf '%s\n' "$PUBLISH" | grep -qF 'does not restate the gaps'
}

@test "an existing standing pull request is appended to, never duplicated" {
  printf '%s\n' "$PUBLISH" | grep -qF 'do **not** open a second'
  printf '%s\n' "$PUBLISH" | grep -qF 'step 3 put you on'
}

@test "more than one standing pull request is reported, never guessed" {
  printf '%s\n' "$SETUP" | grep -qF 'prints more than one'
  printf '%s\n' "$SETUP" | grep -qF 'do not guess'
  printf '%s\n' "$SETUP" | grep -qF 'does not wait for that answer'
}

@test "the finish flow publishes without a confirmation" {
  grep -qF 'Unattended in the finish flow' "$SKILL"
  printf '%s\n' "$PUBLISH" | grep -qF 'publish directly'
  printf '%s\n' "$PUBLISH" | grep -qF 'wrap-up is unattended'
}

@test "MUST publishes unattended in the finish flow" {
  local must
  must="$(awk '/^## MUST$/{on=1;next} on&&/^## /{exit} on' "$SKILL" | tr '\n' ' ' | tr -s ' ')"
  printf '%s\n' "$must" | grep -qF 'Publish without asking when the finish flow'
}

@test "the standing lookup matches the title exactly, never through search syntax" {
  printf '%s\n' "$SETUP" | grep -qF 'select(.title =='
  # The default page hides a standing PR beyond it.
  printf '%s\n' "$SETUP" | grep -qF -- '--limit 200'
  printf '%s\n' "$SETUP" | grep -qF 'never through `--search`'
}

@test "MUST carries the final pass, the fixed title and the single-PR rule" {
  local must
  must="$(awk '/^## MUST$/{on=1;next} on&&/^## /{exit} on' "$SKILL" | tr '\n' ' ' | tr -s ' ')"
  printf '%s\n' "$must" | grep -qiF 'final pass'
  printf '%s\n' "$must" | grep -qF 'chore(improve-reviews): improve review skill'
  printf '%s\n' "$must" | grep -qF 'standing pull request'
  printf '%s\n' "$must" | grep -qF 'more than 10 commits'
}

@test "a standing pull request over 10 commits is reported with a merge recommendation" {
  printf '%s\n' "$REPORT" | grep -qF 'greater than 10'
  printf '%s\n' "$REPORT" | grep -qF 'recommend merging'
}

@test "the publish step names the typed call and the checkout it acts on" {
  printf '%s\n' "$PUBLISH" | grep -qF 'pr-open --type review-improvement'
  printf '%s\n' "$PUBLISH" | grep -qF -- '--cwd'
}

@test "MUST publishes through the typed call, never by hand" {
  local must
  must="$(awk '/^## MUST$/{on=1;next} on&&/^## /{exit} on' "$SKILL" | tr '\n' ' ' | tr -s ' ')"
  printf '%s\n' "$must" | grep -qF 'pr-open --type review-improvement'
}
