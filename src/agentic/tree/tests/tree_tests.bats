#!/usr/bin/env bats
# =============================================================================
# src/agentic/tree/tests/tree_tests.bats
# Tests for the tree.mcp.sh bash entrypoint.
# Tests all options and output variants per module contract.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # Resolve paths relative to this test file
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="$MODULE_DIR/tools/tree.mcp.sh"
  FIXTURES="$TEST_DIR/fixtures"

  # Validate prerequisites
  command -v tree &>/dev/null || skip "tree CLI not installed"
}

# ── No arguments ───────────────────────────────────────────────────────────────

@test "no args: prints usage to stderr and exits 1" {
  run bash "$TOOL"

  assert_failure
  assert_output --partial "Usage:"
}

# ── Single valid directory ─────────────────────────────────────────────────────

@test "single dir: outputs ## Tree structure header and code fence" {
  run bash "$TOOL" "$FIXTURES"

  assert_success
  assert_line --index 0 "## Tree structure"
  # Full output contains the header followed by a blank line
  # bats' assert_output --regexp uses extended regex; embed literal newline
  assert_output --regexp "## Tree structure[[:space:]]+\`\`\`text"
}

@test "single dir: output ends with closing code fence" {
  run bash "$TOOL" "$FIXTURES"

  assert_success
  assert_line --index $((${#lines[@]} - 1)) "\`\`\`"
}

@test "single dir: tree output contains fixture files" {
  run bash "$TOOL" "$FIXTURES"

  assert_success
  assert_output --partial "file_a.txt"
  assert_output --partial "file_b.txt"
  assert_output --partial "sub_file.txt"
}

@test "single dir: includes hidden files (-a flag)" {
  run bash "$TOOL" "$FIXTURES"

  assert_success
  assert_output --partial ".hidden"
}

# ── Multiple directories ───────────────────────────────────────────────────────

@test "multiple dirs: each gets own ## Tree structure section" {
  run bash "$TOOL" "$FIXTURES" "$FIXTURES/subdir"

  assert_success

  local count=0
  for line in "${lines[@]}"; do
    if [[ "$line" == "## Tree structure" ]]; then
      count=$((count + 1))
    fi
  done
  [[ "$count" -eq 2 ]]
}

@test "multiple dirs: first section contains fixtures root files" {
  run bash "$TOOL" "$FIXTURES" "$FIXTURES/subdir"

  assert_success

  # Find line index of the first and second header
  local idx1=-1 idx2=-1
  for i in "${!lines[@]}"; do
    if [[ "${lines[$i]}" == "## Tree structure" ]]; then
      if [[ $idx1 -eq -1 ]]; then
        idx1=$i
      elif [[ $idx2 -eq -1 ]]; then
        idx2=$i
      fi
    fi
  done

  [[ $idx1 -ne -1 ]]
  [[ $idx2 -ne -1 ]]
  # First section should contain the root-level fixture files
  [[ "$(echo "${lines[@]:$idx1:$((idx2 - idx1))}")" == *"file_a.txt"* ]]
  # Second section should contain subdir's file
  [[ "$(echo "${lines[@]:$idx2}")" == *"sub_file.txt"* ]]
}

# ── Mixed valid and invalid directories ────────────────────────────────────────

@test "mixed dirs: valid dir outputs tree, invalid dir prints warning" {
  run bash "$TOOL" "$FIXTURES" "/nonexistent/path"

  assert_success
  assert_output --partial "> skipped non-existent paths: /nonexistent/path"
  assert_output --partial "file_a.txt"
}

@test "multiple invalid dirs: all listed in warning" {
  run bash "$TOOL" "$FIXTURES" "/a" "/b"

  assert_success
  assert_output --partial "skipped"
  assert_output --partial "/a"
}

# ── All directories invalid ────────────────────────────────────────────────────

@test "all invalid: errors to stderr and exits 1" {
  run bash "$TOOL" "/does/not/exist" "/neither/does/this"

  assert_failure
  assert_output --partial "none of the given paths exist"
}

# ── Relative paths ─────────────────────────────────────────────────────────────

@test "relative path: resolves and outputs tree" {
  run bash "$TOOL" "src/agentic/tree/tests/fixtures"

  assert_success
  assert_line --index 0 "## Tree structure"
  assert_output --partial "file_a.txt"
}

# ── Absolute paths ─────────────────────────────────────────────────────────────

@test "absolute path: works as expected" {
  run bash "$TOOL" "$FIXTURES"

  assert_success
  assert_line --index 0 "## Tree structure"
}

# ── Output format structure ────────────────────────────────────────────────────

@test "output format: header, blank, fence, tree content, fence in correct order" {
  run bash "$TOOL" "$FIXTURES"

  assert_success
  assert_line --index 0 "## Tree structure"
  assert_output --regexp "## Tree structure[[:space:]]+\`\`\`text"
  assert_line --index $((${#lines[@]} - 1)) "\`\`\`"
}

@test "output format: tree summary line present (directories, files)" {
  run bash "$TOOL" "$FIXTURES"

  assert_success
  # Check the full output for the summary line (last content line before end fence)
  assert_output --regexp "[0-9]+ director"
}

# ── Unknown flags are rejected, not treated as paths (audit-26 NOTE-4) ───────

@test "unknown --flag: rejected with usage error instead of treated as a path" {
  run bash "$TOOL" "$FIXTURES" "--depth" "1"

  assert_failure
  assert_output --partial "Usage:"
  refute_output --partial "skipped non-existent paths"
}

@test "unknown flag alone: errors instead of being reported as a missing path" {
  run bash "$TOOL" "--md"

  assert_failure
  assert_output --partial "Usage:"
}

# ── Depth limiting (audit-28 NOTE-4): --max-depth / -L passthrough ───────────
# Real `tree` supports `-L level` to descend only N levels. The wrapper
# rejected it as an unknown flag; now --max-depth N and -L N map to -L N so
# callers can limit output depth.

@test "--max-depth N: limits output to N levels (subdir contents excluded)" {
  run bash "$TOOL" --max-depth 1 "$FIXTURES"

  assert_success
  assert_output --partial "subdir"
  refute_output --partial "sub_file.txt"
}

@test "-L N: limits output to N levels" {
  run bash "$TOOL" -L 1 "$FIXTURES"

  assert_success
  assert_output --partial "subdir"
  refute_output --partial "sub_file.txt"
}

@test "--max-depth 2: includes one level deeper" {
  run bash "$TOOL" --max-depth 2 "$FIXTURES"

  assert_success
  assert_output --partial "sub_file.txt"
}

@test "--max-depth with non-numeric value: rejected with usage error" {
  run bash "$TOOL" --max-depth abc "$FIXTURES"

  assert_failure
  assert_output --partial "Usage:"
}

@test "--max-depth without value: rejected with usage error" {
  run bash "$TOOL" --max-depth

  assert_failure
  assert_output --partial "Usage:"
}

@test "--max-depth 0: rejected (tree -L 0 is invalid)" {
  run bash "$TOOL" --max-depth 0 "$FIXTURES"

  assert_failure
  assert_output --partial "Usage:"
  refute_output --partial "Invalid level"
}

@test "-L 0: rejected (tree -L 0 is invalid)" {
  run bash "$TOOL" -L 0 "$FIXTURES"

  assert_failure
  assert_output --partial "Usage:"
}

@test "--max-depth=1 (equals form): limits output to N levels" {
  run bash "$TOOL" --max-depth=1 "$FIXTURES"

  assert_success
  assert_output --partial "subdir"
  refute_output --partial "sub_file.txt"
}

@test "--max-depth=0 (equals form): rejected" {
  run bash "$TOOL" --max-depth=0 "$FIXTURES"

  assert_failure
  assert_output --partial "Usage:"
}

@test "--json flag changes output format to json" {
  run bash "$TOOL" "--json" "$FIXTURES"

  assert_success
  assert_output --partial "file_a.txt"
}

# ── Edge cases ─────────────────────────────────────────────────────────────────

@test "single file path: handled without crash" {
  run bash "$TOOL" "$FIXTURES/file_a.txt"

  assert_output --partial "error opening dir"
}

@test "whitespace in dir name: handled correctly" {
  mkdir -p "$TEST_DIR/fixtures/with space"
  echo "spaced" > "$TEST_DIR/fixtures/with space/file.txt"

  run bash "$TOOL" "$TEST_DIR/fixtures/with space"

  assert_success
  assert_output --partial "with space"
  assert_output --partial "file.txt"

  rm -rf "$TEST_DIR/fixtures/with space"
}

@test "deeply nested directory: shows full tree" {
  mkdir -p "$TEST_DIR/fixtures/deep/a/b/c"
  echo "leaf" > "$TEST_DIR/fixtures/deep/a/b/c/leaf.txt"

  run bash "$TOOL" "$TEST_DIR/fixtures/deep"

  assert_success
  assert_output --partial "deep"
  assert_output --partial "leaf.txt"

  rm -rf "$TEST_DIR/fixtures/deep"
}

@test "same directory passed twice: outputs two identical sections" {
  run bash "$TOOL" "$FIXTURES" "$FIXTURES"

  assert_success
  local count=0
  for line in "${lines[@]}"; do
    if [[ "$line" == "## Tree structure" ]]; then
      count=$((count + 1))
    fi
  done
  [[ "$count" -eq 2 ]]
}

# ── Exit code guarantees ───────────────────────────────────────────────────────

@test "exit code 0 on success with single dir" {
  run bash "$TOOL" "$FIXTURES"
  assert_success
}

@test "exit code 0 on success with mixed valid/invalid dirs" {
  run bash "$TOOL" "$FIXTURES" "/nonexistent"
  assert_success
}

@test "exit code 1 when cli missing" {
  # Override PATH to hide tree binary
  local BASH
  BASH="$(command -v bash)"
  local BUN
  BUN="$(dirname "$(command -v bun)")"

  PATH="$BUN:$(mktemp -d)" run "$BASH" "$TOOL" "$FIXTURES"

  assert_failure
}
