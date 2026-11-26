#!/usr/bin/env bats
# =============================================================================
# src/agentic/github/tests/gh-create-pr_tests.bats
# Guards the rule the module owns: a pull request is always referenced by its
# URL — never a bare number, `#<n>`, or "the PR". Assertions are scoped to the
# section that carries the rule, so a reworded-but-correct file passes and a
# rule deleted or weakened fails.
# =============================================================================

# Body of a `## <heading>` section, up to the next `## `, flattened to one line.
section_flat() {
  awk -v h="## $2" '
    $0 == h      { on = 1; next }
    on && /^## / { exit }
    on           { print }
  ' "$1" | tr '\n' ' ' | tr -s ' '
}

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  SKILL="$MODULE_DIR/skills/gh-create-pr/SKILL.md"

  RULE="$(section_flat "$SKILL" 'Reference the PR by its URL')"
}

@test "skill carries a dedicated rule section" {
  [ -n "$RULE" ]
}

@test "rule requires the full URL and bans every bare form" {
  printf '%s\n' "$RULE" | grep -qF 'Reference every pull request by its URL'
  printf '%s\n' "$RULE" | grep -qF 'never a bare number'
  printf '%s\n' "$RULE" | grep -qF '"the PR"'
}

@test "rule recovers a URL and covers a PR that does not exist yet" {
  printf '%s\n' "$RULE" | grep -qF 'gh pr view <url> --json url'
  printf '%s\n' "$RULE" | grep -qF 'has no URL — name the branch'
}

@test "skill assigns after creation, never on the raw create" {
  local open
  open="$(section_flat "$SKILL" 'Open the PR')"
  printf '%s\n' "$open" | grep -qF -- '--assignee @me'
  # Invocation, not prose, must carry the flag.
  printf '%s\n' "$open" | grep -qF -- '[--assignee @me] --no-review'
  # The raw create takes none: a host that validates the login aborts it.
  run grep -qE -- 'gh pr create[^`]*--assignee' <<< "$open"
  [ "$status" -ne 0 ]
}

@test "rule never models the bare number it bans" {
  ! printf '%s\n' "$RULE" | grep -qF 'number-or-url'
  ! printf '%s\n' "$RULE" | grep -qE '(PR|pull request) ?#[0-9]+'
}

@test "Copilot review section verifies the request actually registered" {
  COPILOT="$(section_flat "$SKILL" 'Copilot review')"
  [ -n "$COPILOT" ]
  # The CLI can claim success with no request queued.
  printf '%s\n' "$COPILOT" | grep -qF 'review_requested'
  printf '%s\n' "$COPILOT" | grep -qF 'timeline'
  printf '%s\n' "$COPILOT" | grep -qF 'devbot:gh-review-loop'
}

@test "command sends a requested Copilot review through the verification" {
  CMD="$MODULE_DIR/commands/gh-create-pr.md"
  grep -qF 'review_requested' "$CMD"
}

@test "skill runs the local review loop before the PR when asked" {
  LOCAL="$(section_flat "$SKILL" 'Local review first')"
  [ -n "$LOCAL" ]
  printf '%s\n' "$LOCAL" | grep -qiF 'local review'
  printf '%s\n' "$LOCAL" | grep -qiF 'squash'
  printf '%s\n' "$LOCAL" | grep -qF 'devbot:software-development'
}

@test "skill opens the PR without a Copilot review and asks afterwards" {
  COPILOT="$(section_flat "$SKILL" 'Copilot review')"
  printf '%s\n' "$COPILOT" | grep -qiF 'without a reviewer'
  printf '%s\n' "$COPILOT" | grep -qiF 'ask the user'
  printf '%s\n' "$COPILOT" | grep -qF 'devbot:gh-review-loop'
  # A pull request no longer queues a review nobody asked for.
  ! printf '%s\n' "$COPILOT" | grep -qF 'default for every pull request'
}

@test "every loop runs by default in an automatic run" {
  LOCAL="$(section_flat "$SKILL" 'Local review first')"
  printf '%s\n' "$LOCAL" | grep -qF 'devbot:auto-dev'
  printf '%s\n' "$LOCAL" | grep -qiF 'by default'

  COPILOT="$(section_flat "$SKILL" 'Copilot review')"
  printf '%s\n' "$COPILOT" | grep -qF 'devbot:auto-dev'
  printf '%s\n' "$COPILOT" | grep -qiF 'by default'
}

@test "skill never requests a reviewer at creation" {
  OPEN_PR="$(section_flat "$SKILL" 'Open the PR')"
  # A rejected reviewer aborts creation, so no reviewer flag belongs on it.
  printf '%s\n' "$OPEN_PR" | grep -qF 'aborts creation'
  run grep -qF -- '--reviewer @copilot' <<< "$OPEN_PR"
  [ "$status" -ne 0 ]
}

@test "skill requests Copilot through GraphQL, the only registering path" {
  COPILOT_DEFAULT="$(section_flat "$SKILL" 'Copilot review')"
  printf '%s\n' "$COPILOT_DEFAULT" | grep -qF -- 'requestReviews'
  printf '%s\n' "$COPILOT_DEFAULT" | grep -qF -- 'botIds'
  printf '%s\n' "$COPILOT_DEFAULT" | grep -qF 'That is the only way'
  # The alias reports success while requesting nobody, so it must not appear
  # as an instruction anywhere in the section.
  alias_lines="$(printf '%s\n' "$COPILOT_DEFAULT" | grep -F -- 'gh pr edit <url> --add-reviewer' || true)"
  [ -z "${alias_lines}" ]
  printf '%s\n' "$COPILOT_DEFAULT" | grep -qF 'review_requested'
}

@test "skill waits one second before verifying the request" {
  COPILOT_DEFAULT="$(section_flat "$SKILL" 'Copilot review')"
  printf '%s\n' "$COPILOT_DEFAULT" | grep -qF -- '--paginate'
  printf '%s\n' "$COPILOT_DEFAULT" | grep -qF 'sleep 1'
}

@test "command asks the local-review question without touching the branch" {
  local cmd="$MODULE_DIR/commands/gh-create-pr.md"
  local step3
  step3="$(awk '/^3\. \*\*Local review gate/{on=1} on && /^4\. Ask the user/{exit} on' "$cmd" | tr '\n' ' ' | tr -s ' ')"

  [ -n "$step3" ]
  printf '%s\n' "$step3" | grep -qF 'the question, not the run'
  printf '%s\n' "$step3" | grep -qF 'devbot:auto-dev'
  # Nothing is written before the plan is approved, so neither appears here.
  run grep -qF 'gh pr create' <<< "$step3"
  [ "$status" -ne 0 ]
  run grep -qiF 'squash' <<< "$step3"
  [ "$status" -ne 0 ]
}

@test "command reviews and squashes only after approval, before it creates the PR" {
  local cmd="$MODULE_DIR/commands/gh-create-pr.md"
  local step6 step7 review_at create_at
  step6="$(awk '/^6\. Show the user/{on=1} on && /^7\. On approval/{exit} on' "$cmd" | tr '\n' ' ' | tr -s ' ')"
  step7="$(awk '/^7\. On approval/{on=1} on && /^8\. Ask the user/{exit} on' "$cmd" | tr '\n' ' ' | tr -s ' ')"

  # The approval gate comes first, and an automatic run is the stated exception.
  printf '%s\n' "$step6" | grep -qF 'wait for explicit approval'
  printf '%s\n' "$step6" | grep -qF 'devbot:auto-dev'

  printf '%s\n' "$step7" | grep -qF 'run the local review when step 3 answered yes'
  printf '%s\n' "$step7" | grep -qF 'refresh the body'
  printf '%s\n' "$step7" | grep -qF 'gh pr create --base'
  # Carried by the tool invocation, not a second edit.
  printf '%s\n' "$step7" | grep -qF -- '[--draft] [--assignee @me] --no-review'
  # And never on the raw create: a host that validates the login aborts it.
  run grep -qE -- 'gh pr create[^`]*--assignee' <<< "$step7"
  [ "$status" -ne 0 ]
  review_at="$(printf '%s' "$step7" | grep -bo 'run the local review' | head -1 | cut -d: -f1)"
  create_at="$(printf '%s' "$step7" | grep -bo 'gh pr create' | head -1 | cut -d: -f1)"
  [ "${review_at:-0}" -lt "${create_at:-0}" ]
}

@test "command gates on the local review and asks about Copilot after the PR" {
  local cmd="$MODULE_DIR/commands/gh-create-pr.md"
  # Step 7 flattened: creation, the ask, and every loop instruction inside it.
  local step7
  step7="$(awk '/^7\. On approval/{on=1} on && /^8\. Print/{exit} on' "$cmd" | tr '\n' ' ' | tr -s ' ')"

  grep -qiF 'local review' "$cmd"
  printf '%s\n' "$step7" | grep -qF 'without a reviewer'
  # One matcher carries the ordering: the ask, then the conditional request.
  printf '%s\n' "$step7" | grep -qF 'Copilot review loop now (`devbot:gh-review-loop`). Only on a yes, request the review'
  # The loop is reachable only through the yes.
  printf '%s\n' "$step7" | grep -qF 'On a yes, run `devbot:gh-review-loop`'
  printf '%s\n' "$step7" | grep -qF 'On a no, stop at the URL'
  # Never-passed flag: no reviewer at creation.
  run grep -qF -- '--reviewer @copilot' "$cmd"
  [ "$status" -ne 0 ]
  run grep -qF -- 'gh pr create' "$cmd"
  [ "$status" -eq 0 ]
  run grep -qF 'gh pr create --base <default> --head <branch> --title' "$cmd"
  [ "$status" -eq 0 ]
  grep -qF 'Do not pass `--reviewer` to `gh pr create`' "$cmd"
  grep -qF 'Do not use `gh pr edit --add-reviewer @copilot`' "$cmd"
}
