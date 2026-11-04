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
  printf '%s\n' "$COPILOT" | grep -qF 'devbot:auto-dev'
}

@test "command sends a requested Copilot review through the verification" {
  CMD="$MODULE_DIR/commands/gh-create-pr.md"
  grep -qF 'review_requested' "$CMD"
}

@test "skill makes the Copilot request the default with an explicit opt-out" {
  COPILOT="$(section_flat "$SKILL" 'Copilot review')"
  printf '%s\n' "$COPILOT" | grep -qF 'default for every pull request'
  printf '%s\n' "$COPILOT" | grep -qF 'skip it only when the user explicitly asked to'
}

@test "skill never requests a reviewer at creation" {
  OPEN_PR="$(section_flat "$SKILL" 'Open the PR')"
  # A rejected reviewer aborts creation, so the flag must not be on it.
  printf '%s\n' "$OPEN_PR" | grep -qF 'No `--reviewer` here'
  ! printf '%s\n' "$OPEN_PR" | grep -qF -- '--reviewer @copilot'
}

@test "skill requests Copilot after creation and verifies it" {
  COPILOT_DEFAULT="$(section_flat "$SKILL" 'Copilot review')"
  printf '%s\n' "$COPILOT_DEFAULT" | grep -qF 'default for every pull request'
  printf '%s\n' "$COPILOT_DEFAULT" | grep -qF -- 'gh pr edit <url>'
  printf '%s\n' "$COPILOT_DEFAULT" | grep -qF -- '--add-reviewer @copilot'
  printf '%s\n' "$COPILOT_DEFAULT" | grep -qF 'review_requested'
}

@test "skill pages the verification and re-checks after the fallback" {
  COPILOT_DEFAULT="$(section_flat "$SKILL" 'Copilot review')"
  printf '%s\n' "$COPILOT_DEFAULT" | grep -qF -- '--paginate'
  printf '%s\n' "$COPILOT_DEFAULT" | grep -qF 're-read the timeline'
}

@test "command creates without a reviewer and requests Copilot afterwards" {
  local cmd="$MODULE_DIR/commands/gh-create-pr.md"
  grep -qF 'Copilot review is requested by default' "$cmd"
  ! grep -qF -- '--reviewer @copilot' "$cmd"
  grep -qF -- 'gh pr edit <url> --add-reviewer @copilot' "$cmd"
  grep -qF 'requested by default after the PR exists' "$cmd"
  grep -qF 'only when the user explicitly asked to' "$cmd"
  grep -qF 'Do not pass `--reviewer` to `gh pr create`' "$cmd"
}
