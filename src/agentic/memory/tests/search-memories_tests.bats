#!/usr/bin/env bats
# =============================================================================
# src/agentic/memory/tests/search-memories_tests.bats
# Tests for the search-memories bash entrypoint.
# Covers CLI wrapper behavior, error handling, and argument forwarding.
# =============================================================================

setup() {
  local bats_lib
  bats_lib="$(npm root -g 2>/dev/null || echo /usr/local/lib/node_modules)"
  load "${bats_lib}/bats-support/load.bash"
  load "${bats_lib}/bats-assert/load.bash"

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="$MODULE_DIR/tools/search-memories/search-memories.sh"
  PYTHON_SCRIPT="$MODULE_DIR/tools/search-memories/search-memories.py"
  FIXTURES="$TEST_DIR/fixtures"
  BASH="$(command -v bash)"
}

teardown() {
  # Clean up any temp files/dirs left by test failures (early assertion exits)
  find "$FIXTURES" -maxdepth 1 -name 'tmp.*' -exec rm -rf {} + 2>/dev/null || true
}

# ── Help flag ─────────────────────────────────────────────────────────────────

@test "--help: prints usage and exits 0" {
  command -v python3 &>/dev/null || skip "python3 not installed"

  run "$BASH" "$TOOL" --help

  assert_success
  assert_output --partial "usage:"
  assert_output --partial "search-memories"
}

# ── Missing dependencies ──────────────────────────────────────────────────────

@test "python script missing: clear error when search-memories.py not found" {
  local tmpfile
  tmpfile="$(mktemp -p "$FIXTURES" tmp.XXXXXX.py)"
  mv "$PYTHON_SCRIPT" "$tmpfile"

  run "$BASH" "$TOOL" "test"

  assert_failure
  assert_output --partial "Error"
  assert_output --partial "search-memories.py not found"

  mv "$tmpfile" "$PYTHON_SCRIPT"
}

@test "python3 returns non-zero: error propagated to caller" {
  local mockdir
  mockdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$mockdir/python3" <<'SCRIPT'
#!/bin/bash
echo "mock python3 failure" >&2
exit 1
SCRIPT
  chmod +x "$mockdir/python3"

  PATH="$mockdir:/usr/bin:/bin" run "$BASH" "$TOOL" "test"

  assert_failure
  assert_output --partial "mock python3 failure"

  rm -rf "$mockdir"
}

# ── Argument forwarding (mock python3 echoes args) ────────────────────────────

@test "positional args: each becomes a --query value" {
  local mockdir
  mockdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$mockdir/python3" <<'SCRIPT'
#!/bin/bash
# Echo args so we can verify the bash wrapper passes them correctly
echo "$*"
SCRIPT
  chmod +x "$mockdir/python3"

  PATH="$mockdir:/usr/bin:/bin" run "$BASH" "$TOOL" "billing erp"

  assert_success
  assert_output --regexp "\-\-query.*billing erp"

  rm -rf "$mockdir"
}

@test "multiple positional args: each becomes a separate --query" {
  local mockdir
  mockdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$mockdir/python3" <<'SCRIPT'
#!/bin/bash
echo "$*"
SCRIPT
  chmod +x "$mockdir/python3"

  PATH="$mockdir:/usr/bin:/bin" run "$BASH" "$TOOL" "query1" "query2"

  assert_success
  assert_output --regexp "\-\-query.*query1.*\-\-query.*query2"

  rm -rf "$mockdir"
}

@test "--json flag: sets format to json" {
  local mockdir
  mockdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$mockdir/python3" <<'SCRIPT'
#!/bin/bash
echo "$*"
SCRIPT
  chmod +x "$mockdir/python3"

  PATH="$mockdir:/usr/bin:/bin" run "$BASH" "$TOOL" --json "test"

  assert_success
  assert_output --regexp "\-\-format json"

  rm -rf "$mockdir"
}

@test "--format <value>: two-token form" {
  local mockdir
  mockdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$mockdir/python3" <<'SCRIPT'
#!/bin/bash
echo "$*"
SCRIPT
  chmod +x "$mockdir/python3"

  PATH="$mockdir:/usr/bin:/bin" run "$BASH" "$TOOL" --format json "test"

  assert_success
  assert_output --regexp "\-\-format json"

  rm -rf "$mockdir"
}

@test "--format=<value>: embedded form" {
  local mockdir
  mockdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$mockdir/python3" <<'SCRIPT'
#!/bin/bash
echo "$*"
SCRIPT
  chmod +x "$mockdir/python3"

  PATH="$mockdir:/usr/bin:/bin" run "$BASH" "$TOOL" "--format=json" "test"

  assert_success
  assert_output --regexp "\-\-format json"

  rm -rf "$mockdir"
}

@test "--collection and --max-results: passed through to python" {
  local mockdir
  mockdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$mockdir/python3" <<'SCRIPT'
#!/bin/bash
echo "$*"
SCRIPT
  chmod +x "$mockdir/python3"

  # Use --collection=<value> and --max-results=<value> forms since the
  # bash wrapper only pairs --format with its value via a second parsing pass.
  PATH="$mockdir:/usr/bin:/bin" run "$BASH" "$TOOL" \
    "--collection=myproject" "--max-results=10" "test"

  assert_success
  assert_output --regexp "\-\-collection.*myproject"
  assert_output --regexp "\-\-max-results.*10"

  rm -rf "$mockdir"
}

@test "combined flags: --json --collection --max-results with query" {
  local mockdir
  mockdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$mockdir/python3" <<'SCRIPT'
#!/bin/bash
echo "$*"
SCRIPT
  chmod +x "$mockdir/python3"

  PATH="$mockdir:/usr/bin:/bin" run "$BASH" "$TOOL" \
    --json \
    --collection=core \
    --max-results=20 \
    "testing"

  assert_success
  assert_output --regexp "\-\-format json"
  assert_output --regexp "\-\-collection.*core"
  assert_output --regexp "\-\-max-results.*20"
  assert_output --regexp "\-\-query.*testing"

  rm -rf "$mockdir"
}

# ── Two-token --collection and --max-results forwarding ──────────────────────
# These test the fix for the bug where "--collection myproj" would drop "myproj"
# as a search query instead of forwarding it as the collection value.

@test "--collection <value> two-token form: value forwarded, not treated as query" {
  local mockdir
  mockdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$mockdir/python3" <<'SCRIPT'
#!/bin/bash
echo "$*"
SCRIPT
  chmod +x "$mockdir/python3"

  PATH="$mockdir:/usr/bin:/bin" run "$BASH" "$TOOL" --collection myproject "test-query"

  assert_success
  assert_output --regexp "\-\-collection\b.*myproject"
  assert_output --regexp "\-\-query.*test-query"
  # "myproject" should NOT appear as a query value
  refute_output --regexp "\-\-query[[:space:]]+myproject"

  rm -rf "$mockdir"
}

@test "--max-results <value> two-token form: value forwarded, not treated as query" {
  local mockdir
  mockdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$mockdir/python3" <<'SCRIPT'
#!/bin/bash
echo "$*"
SCRIPT
  chmod +x "$mockdir/python3"

  PATH="$mockdir:/usr/bin:/bin" run "$BASH" "$TOOL" --max-results 15 "search-term"

  assert_success
  assert_output --regexp "\-\-max-results\b.*15"
  assert_output --regexp "\-\-query.*search-term"
  # "15" should NOT appear as a query value
  refute_output --regexp "\-\-query[[:space:]]+15"

  rm -rf "$mockdir"
}

@test "both two-token forms together: --collection X --max-results N query" {
  local mockdir
  mockdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$mockdir/python3" <<'SCRIPT'
#!/bin/bash
echo "$*"
SCRIPT
  chmod +x "$mockdir/python3"

  PATH="$mockdir:/usr/bin:/bin" run "$BASH" "$TOOL" \
    --collection core \
    --max-results 8 \
    "memory-test"

  assert_success
  assert_output --regexp "\-\-collection\b.*core"
  assert_output --regexp "\-\-max-results\b.*8"
  assert_output --regexp "\-\-query.*memory-test"
  # Values should NOT leak into queries
  refute_output --regexp "\-\-query[[:space:]]+core"
  refute_output --regexp "\-\-query[[:space:]]+8"

  rm -rf "$mockdir"
}

@test "--format <value> two-token form: value forwarded, query preserved" {
  local mockdir
  mockdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$mockdir/python3" <<'SCRIPT'
#!/bin/bash
echo "$*"
SCRIPT
  chmod +x "$mockdir/python3"

  PATH="$mockdir:/usr/bin:/bin" run "$BASH" "$TOOL" --format json "search-term"

  assert_success
  assert_output --regexp "\-\-format\b.*json"
  assert_output --regexp "\-\-query.*search-term"

  rm -rf "$mockdir"
}

@test "mixed embedded and two-token forms work together" {
  local mockdir
  mockdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$mockdir/python3" <<'SCRIPT'
#!/bin/bash
echo "$*"
SCRIPT
  chmod +x "$mockdir/python3"

  # --collection=foo (embedded) and --max-results 10 (two-token)
  PATH="$mockdir:/usr/bin:/bin" run "$BASH" "$TOOL" \
    --collection=embedded \
    --max-results 10 \
    "query-term"

  assert_success
  assert_output --regexp "\-\-collection\b.*embedded"
  assert_output --regexp "\-\-max-results\b.*10"
  assert_output --regexp "\-\-query.*query-term"

  rm -rf "$mockdir"
}

# ── Edge cases with real python3 ──────────────────────────────────────────────

@test "no positional args: argparse error about missing --query" {
  command -v python3 &>/dev/null || skip "python3 not installed"

  run "$BASH" "$TOOL"

  assert_failure
  assert_output --partial "--query"
}

@test "qmd not installed: returns clear error message" {
  command -v python3 &>/dev/null || skip "python3 not installed"
  command -v qmd &>/dev/null && skip "qmd is installed — this test requires qmd absence"

  run "$BASH" "$TOOL" "test"

  assert_failure
  assert_output --partial "qmd CLI not found"
}

# ── Output format integrity ───────────────────────────────────────────────────

@test "--markdown flag: sets format to markdown" {
  local mockdir
  mockdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$mockdir/python3" <<'SCRIPT'
#!/bin/bash
echo "$*"
SCRIPT
  chmod +x "$mockdir/python3"

  PATH="$mockdir:/usr/bin:/bin" run "$BASH" "$TOOL" --markdown "test"

  assert_success
  assert_output --regexp "\-\-format markdown"

  rm -rf "$mockdir"
}

@test "special characters in query: passed through" {
  local mockdir
  mockdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$mockdir/python3" <<'SCRIPT'
#!/bin/bash
echo "$*"
SCRIPT
  chmod +x "$mockdir/python3"

  # Use a query with shell-special characters to verify unmolested passthrough
  PATH="$mockdir:/usr/bin:/bin" run "$BASH" "$TOOL" 'query with :: slashes /path/name'

  assert_success
  assert_output --partial "query with :: slashes /path/name"

  rm -rf "$mockdir"
}
