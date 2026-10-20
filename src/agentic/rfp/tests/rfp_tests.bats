#!/usr/bin/env bats
# =============================================================================
# src/agentic/rfp/tests/rfp_tests.bats
# Guards the rfp module's contract: lifecycle scripts, the shared wrapper, the
# command/skill frontmatter, and the rubric sections the workflow depends on.
# =============================================================================

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  SKILL="$MODULE_DIR/skills/rfp/SKILL.md"
  COMMAND="$MODULE_DIR/commands/rfp.md"
  DOCS="$MODULE_DIR/docs.md"
}

@test "functions.sh sources the shared library" {
  grep -q '_shared/functions.sh' "$MODULE_DIR/functions.sh"
}

@test "lifecycle scripts exist and are executable" {
  for f in install.sh pre.sh update.sh; do
    [ -f "$MODULE_DIR/$f" ]
    [ -x "$MODULE_DIR/$f" ]
  done
}

@test "skill frontmatter names devbot:rfp" {
  run sed -n '1,6p' "$SKILL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: devbot:rfp"* ]]
}

@test "command frontmatter names devbot:rfp" {
  run sed -n '1,6p' "$COMMAND"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: devbot:rfp"* ]]
}

@test "command uses the first argument as the questionnaire path" {
  grep -q '\$1' "$COMMAND"
  ! grep -q '\$ARGUMENTS' "$COMMAND"
  grep -qi 'argument #1' "$COMMAND"
  grep -q 'carries a risk statement, asks for compensating controls, or asks for an explanation' "$COMMAND"
}

@test "skill documents the knowledge-base input" {
  grep -q '.agents/memory/reference' "$SKILL"
}

@test "skill requires the questionnaire's own answer options" {
  grep -qi "questionnaire's own options" "$SKILL"
  grep -qi "Never write \"Partial\"" "$SKILL"
}

@test "skill covers risk responses for Yes and No answers" {
  grep -q '^### 4\. Risk responses' "$SKILL"
  grep -qi 'whether the answer is Yes or No' "$SKILL"
}

@test "skill defines the client-facing tone rules" {
  grep -q '^## Tone rules' "$SKILL"
  grep -q '^## What not to do' "$SKILL"
}

@test "skill defines a quality gate" {
  grep -q '^### 6. Gate' "$SKILL"
  grep -q 'Every question has either an answer' "$SKILL"
}

@test "docs.md declares the command and skill" {
  run sed -n '1,8p' "$DOCS"
  [ "$status" -eq 0 ]
  [[ "$output" == *'commands: ["rfp"]'* ]]
  [[ "$output" == *'skills: ["rfp"]'* ]]
  grep -q 'carries a risk statement, asks for compensating controls, or asks for an explanation' "$DOCS"
}

@test "skill closes the review findings" {
  grep -q 'Do not use a CSV conversion for a multi-sheet questionnaire' "$SKILL"
  grep -q 'No committed target date' "$SKILL"
  grep -q 'only output that carries source paths' "$SKILL"
  grep -q 'No compensating control is documented' "$SKILL"
  grep -q 'not only `Yes`' "$SKILL"
  grep -q 'inlineStr' "$SKILL"
  grep -q 'No approved remediation plan is documented' "$SKILL"
  grep -q 'Flagged for review' "$SKILL"
  grep -q 'carries a risk statement, asks for compensating controls, or asks for an explanation' "$SKILL"
  grep -q 'untrusted client data' "$SKILL"
  grep -q 'sanitized-question-id' "$SKILL"
  grep -q 'Detect the answer schema \*\*per question\*\*' "$SKILL"
  grep -q 'choose exactly one outcome' "$SKILL"
  grep -q 'single safe path component' "$SKILL"
  grep -q 'deterministic disambiguator' "$SKILL"
  grep -q 'complete `<slug>`' "$SKILL"
  grep -q 'Do not both answer and flag' "$SKILL"
  grep -q 'assign a deterministic id first' "$SKILL"
  grep -q 'appropriate to its schema' "$SKILL"
  grep -q 'asks for compensating controls' "$SKILL"
  grep -q 'negative option when one is offered' "$SKILL"
  grep -q 'or "Flagged for review" when the question has no valid option' "$SKILL"
  grep -q 'canonical `docs/Tenders` root' "$SKILL"
  grep -q 'Never overwrite the questionnaire' "$SKILL"
  grep -q 'documents that the control is absent' "$SKILL"
  grep -q 'reject a symlinked output file' "$SKILL"
}

@test "lifecycle scripts provision and check PDF extraction" {
  grep -q 'poppler-utils' "$MODULE_DIR/install.sh"
  grep -q 'pdftotext' "$MODULE_DIR/pre.sh"
}
