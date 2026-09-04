#!/usr/bin/env bats
# =============================================================================
# src/agentic/memory/tests/search-memories_tests.bats
# Tests for the search-memories bash entrypoint.
# Covers CLI wrapper behavior, error handling, and argument forwarding.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="$MODULE_DIR/tools/search-memories/search-memories.mcp.sh"
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
  # Run the wrapper from an isolated copy WITHOUT search-memories.py, so its
  # SCRIPT_DIR lookup finds no implementation. (Don't mv the real source — a
  # failing assertion would leave it deleted, and teardown would wipe the copy.)
  local iso_dir
  iso_dir="$(mktemp -d "$FIXTURES/tmpdir.XXXXXX")"
  cp "$TOOL" "$iso_dir/search-memories.mcp.sh"

  run "$BASH" "$iso_dir/search-memories.mcp.sh" "test"

  assert_failure
  assert_output --partial "search-memories.py not found"

  rm -rf "$iso_dir"
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

# ── --query flag forms (audit-49 NOTE-1) ─────────────────────────────────────
# The wrapper forwarded a literal --query into EXTRA_ARGS without its value, so
# `search-memories --query "phrase"` produced a valueless trailing --query and
# argparse failed with "argument --query: expected one argument". --query must
# behave like the other two-token flags (--collection/--max-results).

@test "--query <value> two-token form: value forwarded, not treated as query" {
  local mockdir
  mockdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$mockdir/python3" <<'SCRIPT'
#!/bin/bash
echo "$*"
SCRIPT
  chmod +x "$mockdir/python3"

  PATH="$mockdir:/usr/bin:/bin" run "$BASH" "$TOOL" --query "planning workflow"

  assert_success
  assert_output --regexp "\-\-query planning workflow"
  # The phrase must not also appear as a separate valueless --query.
  refute_output --regexp "\-\-query[[:space:]]*$"
  rm -rf "$mockdir"
}

@test "--query=<value> embedded form: passed through to python" {
  local mockdir
  mockdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$mockdir/python3" <<'SCRIPT'
#!/bin/bash
echo "$*"
SCRIPT
  chmod +x "$mockdir/python3"

  PATH="$mockdir:/usr/bin:/bin" run "$BASH" "$TOOL" "--query=planning" "--max-results=3"

  assert_success
  assert_output --regexp "\-\-query=planning"
  assert_output --regexp "\-\-max-results.*3"
  rm -rf "$mockdir"
}

@test "audit-49 repro: --query phrase --max-results n parses end to end" {
  local mockdir
  mockdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$mockdir/python3" <<'SCRIPT'
#!/bin/bash
echo "$*"
SCRIPT
  chmod +x "$mockdir/python3"

  PATH="$mockdir:/usr/bin:/bin" run "$BASH" "$TOOL" --query "billing erp" --max-results 3

  assert_success
  assert_output --regexp "\-\-query billing erp"
  assert_output --regexp "\-\-max-results 3"
  # No valueless --query left dangling before the next flag (audit-49 failure).
  refute_output --regexp "\-\-query \-\-max-results"
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

  # Hide qmd (but keep python3, which the wrapper execs) so this error path is
  # exercised regardless of the host's qmd installation. Strip the directory
  # containing `qmd` from PATH rather than blanking PATH entirely.
  local qmd_dir filtered_path dir
  qmd_dir="$(dirname "$(command -v qmd 2>/dev/null)")"
  filtered_path=""
  while IFS= read -r -d: dir; do
    [[ -n "$dir" && "$dir" != "$qmd_dir" ]] || continue
    filtered_path="${filtered_path:+$filtered_path:}$dir"
  done <<< "${PATH}:"
  PATH="$filtered_path" run "$BASH" "$TOOL" "test"

  assert_failure
  assert_output --partial "qmd CLI not found"
}

# ── Default collection resolution (audit-32/33 FAIL) ──────────────────────────
# resolve_collection() must mirror qmd/init.sh: fall back to the project dir
# basename when .devbot.project.jsonc is missing, unreadable, or lacks a
# (non-empty) project_name — not to a hardcoded "devbot" collection that was
# never registered ("Collection not found: devbot").

@test "resolve_collection: falls back to dir basename when project_name absent" {
  command -v python3 &>/dev/null || skip "python3 not installed"

  local proj_dir
  proj_dir="$(mktemp -d "$FIXTURES/proj.XXXXXX")"
  # No project_name key — the audit-32/33 fixture shape (harness/modules only).
  cat > "$proj_dir/.devbot.project.jsonc" <<'JSON'
{"harness": "opencode", "modules": {}}
JSON

  run python3 -c "
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location('sm', '$MODULE_DIR/tools/search-memories/search-memories.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(m.resolve_collection(Path('$proj_dir')))
"

  assert_success
  assert_output "$(basename "$proj_dir")"

  rm -rf "$proj_dir"
}

@test "resolve_collection: empty project_name also falls back to dir basename" {
  command -v python3 &>/dev/null || skip "python3 not installed"

  local proj_dir
  proj_dir="$(mktemp -d "$FIXTURES/proj.XXXXXX")"
  printf '{"project_name": ""}\n' > "$proj_dir/.devbot.project.jsonc"

  run python3 -c "
import importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location('sm', '$MODULE_DIR/tools/search-memories/search-memories.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(m.resolve_collection(Path('$proj_dir')))
"

  assert_success
  assert_output "$(basename "$proj_dir")"

  rm -rf "$proj_dir"
}

@test "resolve_collection: project_name from config wins over dir basename" {
  command -v python3 &>/dev/null || skip "python3 not installed"

  local proj_dir
  proj_dir="$(mktemp -d "$FIXTURES/proj.XXXXXX")"
  printf '{"project_name": "my-cool-project"}\n' > "$proj_dir/.devbot.project.jsonc"

  run python3 -c "
import importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location('sm', '$MODULE_DIR/tools/search-memories/search-memories.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(m.resolve_collection(Path('$proj_dir')))
"

  assert_success
  assert_output "my-cool-project"

  rm -rf "$proj_dir"
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
