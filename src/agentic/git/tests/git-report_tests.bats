#!/usr/bin/env bats
# =============================================================================
# src/agentic/git-report/tests/git-report_tests.bats
# Tests for the git-report bash entrypoint.
# Tests from the bash entrypoint, covering all options and outputs.
# =============================================================================

setup() {
  bats_require_minimum_version 1.5.0
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="$MODULE_DIR/tools/git-report.mcp.sh"

  # Create a temporary git repo for testing
  REPO="$(mktemp -d)"
  git -C "$REPO" init --initial-branch=main &>/dev/null
  git -C "$REPO" config user.email "test@test.com"
  git -C "$REPO" config user.name "Test"
  # Hermetic: don't inherit the developer's global commit.gpgsign — signing
  # every test commit (gpg agent round-trip ~1.3s) makes the suite crawl.
  git -C "$REPO" config commit.gpgsign false
  echo "initial" > "$REPO/file.txt"
  git -C "$REPO" add -A && git -C "$REPO" commit -m "initial commit" &>/dev/null

  command -v python3 &>/dev/null || skip "python3 not installed"
}

teardown() {
  rm -rf "$REPO" 2>/dev/null || true
}

# Helper: run tool in the test repo directory
run_tool() {
  run bash -c "cd '$REPO' && bash '$TOOL' $*"
}

# ── Default (no args) ─────────────────────────────────────────────────────────

@test "default: outputs Git Report header" {
  run_tool

  assert_success
  assert_line --index 0 "## Git Report"
}

@test "default: no origin remote reports unknown without dead set-head advice" {
  # The setup repo has no `origin` remote at all. The tool already runs
  # `git remote set-head origin --auto` internally (best-effort) and it cannot
  # succeed without an origin — so the fallback must say "no remote configured",
  # not suggest a command that was already tried and will fail again
  # (audit-19 incidental NOTE).
  run_tool

  assert_success
  assert_output --partial "(unknown — no remote configured)"
  refute_output --partial "git remote set-head origin --auto"
}

@test "default: shows current branch" {
  run_tool

  assert_success
  assert_output --partial "**Current branch:**"
}

@test "default: shows recent commits" {
  run_tool

  assert_success
  assert_output --partial "### Recent Commits"
}

@test "default: shows status section" {
  run_tool

  assert_success
  assert_output --partial "### Status"
}

@test "default: shows staged changes section" {
  run_tool

  assert_success
  assert_output --partial "### Staged Changes"
}

# ── --log-count flag ──────────────────────────────────────────────────────────

@test "--log-count 3: shows exactly 3 commits" {
  # Add 5 more commits
  for i in 1 2 3 4 5; do
    echo "change $i" >> "$REPO/file.txt"
    git -C "$REPO" add -A && git -C "$REPO" commit -m "commit $i" &>/dev/null
  done

  run_tool --log-count 3

  assert_success
  # Count bullet-point commit lines
  local count=0
  while IFS= read -r line; do
    if [[ "$line" == "- "* ]]; then
      count=$((count + 1))
    fi
  done <<< "$output"
  [[ "$count" -eq 3 ]]
}

@test "--log-count 0: shows no commits placeholder" {
  run_tool --log-count 0

  assert_success
  assert_output --partial "_(no commits)_"
}

# ── Working directory state ───────────────────────────────────────────────────

@test "dirty working tree: status reflects uncommitted changes" {
  echo "dirty" >> "$REPO/file.txt"
  git -C "$REPO" add file.txt

  run_tool

  assert_success
  assert_output --partial "Changes to be committed"
}

@test "clean working tree: status shows clean" {
  run_tool

  assert_success
  assert_output --partial "working tree clean"
}

# ── Staged changes ────────────────────────────────────────────────────────────

@test "staged changes: shows diff when something is staged" {
  echo "staged_content" > "$REPO/new_file.txt"
  git -C "$REPO" add new_file.txt

  run_tool

  assert_success
  assert_output --partial "### Staged Changes (summary)"
  assert_output --partial "new_file.txt"
}

@test "nothing staged: shows placeholder" {
  run_tool

  assert_success
  assert_output --partial "_(nothing staged)_"
}

# ── Output format ─────────────────────────────────────────────────────────────

@test "output: sections appear in correct order" {
  run_tool

  assert_success
  local header_lines=(
    "## Git Report"
    "### Recent Commits"
    "### Status"
    "### Staged Changes (summary)"
    "### Commits Unique to Current Branch"
    "### Index Integrity"
  )

  local last_idx=-1
  for header in "${header_lines[@]}"; do
    for i in "${!lines[@]}"; do
      if [[ "${lines[$i]}" == "$header" ]]; then
        [[ $i -gt $last_idx ]]
        last_idx=$i
        break
      fi
    done
  done
}

@test "output: uses code fences around status block" {
  run_tool

  assert_success
  assert_output --regexp '\`\`\`'
}

@test "output: no --json flag accepted (argparse error)" {
  run -2 bash -c "cd '$REPO' && bash '$TOOL' --json 2>&1"

  assert_output --partial "unrecognized arguments"
}

@test "output: --markdown flag not accepted" {
  run -2 bash -c "cd '$REPO' && bash '$TOOL' --markdown 2>&1"

  assert_output --partial "unrecognized arguments"
}

# ── Exit code guarantees ──────────────────────────────────────────────────────

@test "exit code 0 on success" {
  run_tool
  assert_success
}

@test "outside git repo: shows empty branch and no commits gracefully" {
  local tmpdir
  tmpdir="$(mktemp -d)"

  run bash -c "cd '$tmpdir' && bash '$TOOL' 2>&1"

  assert_success
  assert_line --index 0 "## Git Report"
  assert_output --partial "Current branch:** \`\`"
  assert_output --partial "_(no commits)_"

  rm -rf "$tmpdir"
}
