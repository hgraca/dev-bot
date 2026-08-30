#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
  FIXTURES="$TEST_DIR/fixtures"
  mkdir -p "$FIXTURES"
}

teardown() {
  find "$FIXTURES" -maxdepth 1 -name 'tmp.*' -exec rm -rf {} + 2>/dev/null || true
}

# ── tree.mcp.sh ────────────────────────────────────────────────────────────────────

@test "tool tree: outputs tree structure for a directory" {
  run bash "${PROJECT_ROOT}/src/agentic/tree/tools/tree.mcp.sh" "${PROJECT_ROOT}/src/agentic/tree"
  assert_success
  [[ "$output" == *"## Tree structure"* ]] || fail "expected '## Tree structure' header (got: ${output:0:200})"
  [[ "$output" == *"tree.mcp.sh"* ]] || fail "expected tool filename in output"
}

@test "tool tree: fails with usage when no dir given" {
  run bash "${PROJECT_ROOT}/src/agentic/tree/tools/tree.mcp.sh"
  assert_failure
  [[ "$output" == *"Usage"* ]] || fail "expected Usage message"
}

# ── format-md.mcp.sh ───────────────────────────────────────────────────────────────

@test "tool format-md: aligns markdown table columns" {
  local test_file
  test_file="$(mktemp "$FIXTURES/tmp.XXXXXX.md")"
  cat > "$test_file" << 'EOF'
| a | b |
|---|---|
| 1 | 2 |
EOF

  run bash "${PROJECT_ROOT}/src/agentic/format-md/tools/format-md.mcp.sh" "$test_file"
  assert_success

  # Read the formatted file and check alignment
  run cat "$test_file"
  # After formatting, columns should be aligned (padded with spaces)
  grep -qE '^\| a\s+\| b\s+\|$' <<< "$output" || fail "table columns not aligned (got: $output)"
  rm -f "$test_file"
}

@test "tool format-md: pipes stdin to stdout when no file arg" {
  run bash "${PROJECT_ROOT}/src/agentic/format-md/tools/format-md.mcp.sh" << 'EOF'
| x | y |
|---|---|
| 1 | 2 |
EOF
  assert_success
  [[ "$output" == *"| x"* ]] || fail "expected table in output"
  [[ "$output" == *"| 1"* ]] || fail "expected data in output"
}

# ── git-report.mcp.sh ──────────────────────────────────────────────────────────────

@test "tool git-report: outputs markdown git state" {
  # Run in the dev-bot repo itself (always a git repo)
  run bash "${PROJECT_ROOT}/src/agentic/git/tools/git-report.mcp.sh"
  assert_success

  [[ "$output" == *"## Git Report"* ]] || fail "expected '## Git Report' header"
  [[ "$output" == *"Current branch"* ]] || fail "expected branch info"
  [[ "$output" == *"### Recent Commits"* ]] || fail "expected '### Recent Commits' section"
}

@test "tool git-report: --log-count limits commit output" {
  run bash "${PROJECT_ROOT}/src/agentic/git/tools/git-report.mcp.sh" --log-count 3
  assert_success

  # Count commit markers (should be 3 or less)
  local count
  count="$(grep -c '^| [a-f0-9]' <<< "$output" || true)"
  [[ "$count" -le 3 ]] || fail "expected <= 3 commits, got $count"
}

# ── qmd.mcp.sh ─────────────────────────────────────────────────────────────────────

@test "tool qmd: runs status command" {
  if ! command -v qmd &>/dev/null; then
    skip "qmd CLI not available"
  fi

  run bash "${PROJECT_ROOT}/src/agentic/qmd/tools/qmd.mcp.sh" status
  assert_success
  [[ "$output" == *"## QMD output"* ]] || fail "expected QMD output header"
}

@test "tool qmd: --help shows usage" {
  if ! command -v qmd &>/dev/null; then
    skip "qmd CLI not available"
  fi

  run bash "${PROJECT_ROOT}/src/agentic/qmd/tools/qmd.mcp.sh" --help
  assert_success
  [[ "$output" == *"Usage"* ]] || fail "expected usage info"
}

# ── list-projects.mcp.sh ───────────────────────────────────────────────────────────

@test "tool list-projects: exposes mcp-meta" {
  run bash "${PROJECT_ROOT}/src/tools/devbot-cli/tools/list-projects.mcp.sh" mcp-meta
  assert_success
  [[ "$output" == *'"name":"list-projects"'* ]] || fail "expected list-projects name in mcp-meta"
}

@test "tool list-projects: outputs markdown header" {
  run bash "${PROJECT_ROOT}/src/tools/devbot-cli/tools/list-projects.mcp.sh"
  assert_success
  [[ "$output" == *"## Sibling Projects"* ]] || fail "expected '## Sibling Projects' header"
}

# ── agent-communication.mcp.sh ─────────────────────────────────────────────────────

@test "tool agent-communication: validates [FINISHED] status" {
  local tmpfile
  tmpfile="$(mktemp "$FIXTURES/tmp.XXXXXX.json")"

  # Write a test message with [FINISHED] status (uses info.role + parts[] format)
  python3 -c "
import json
msg = {'info': {'role': 'assistant'}, 'parts': [{'type': 'text', 'text': 'Some work\n\n[FINISHED]'}]}
with open('$tmpfile', 'w') as f:
    json.dump(msg, f)
"

  run bash "${PROJECT_ROOT}/src/agentic/agent-communication/tools/agent-communication.mcp.sh" --msg-file "$tmpfile"
  assert_success
  grep -qF 'OK — terminal marker found' <<< "$output" || fail "expected OK (got: ${output:0:300})"

  rm -f "$tmpfile"
}

@test "tool agent-communication: flags missing terminal status" {
  local tmpfile
  tmpfile="$(mktemp "$FIXTURES/tmp.XXXXXX.json")"

  # Write a test message with no terminal status
  python3 -c "
import json
msg = {'info': {'role': 'assistant'}, 'parts': [{'type': 'text', 'text': 'Just some work in progress'}]}
with open('$tmpfile', 'w') as f:
    json.dump(msg, f)
"

  run bash "${PROJECT_ROOT}/src/agentic/agent-communication/tools/agent-communication.mcp.sh" --msg-file "$tmpfile"
  assert_failure
  grep -qF 'Missing terminal marker' <<< "$output" || fail "expected 'Missing terminal marker' (got: ${output:0:300})"

  rm -f "$tmpfile"
}
