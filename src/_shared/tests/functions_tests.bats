#!/usr/bin/env bats
# =============================================================================
# src/functions/tests/functions_tests.bats
# Tests for the _upsert_opencode_plugin function in src/_shared/functions.sh.
#
# Run from project root:
#   bats src/functions/tests/functions_tests.bats
#
# Covers all 12 scenarios from the function contract:
#   1.  Add to non-empty existing array
#   2.  Add to empty existing array ("plugin": [])
#   3.  Multiple sequential adds (idempotent comma handling)
#   4.  No "plugin": [ section — creates new block before closing }
#   5.  Minimal file {} (no fields at all)
#   6.  {} then add second plugin (existing array created by prior call)
#   7.  File not found → exit 1
#   8.  Idempotent: add same entry twice
#   9.  File path entry (.opencode/plugins/devbot/foo.js)
#   10. Full realistic opencode.jsonc layout ($schema, agent, permission, no plugin)
#   11. Entry already present in non-empty array
#   12. Entry with characters needing quoting (dots, hyphens, slashes)
# =============================================================================

setup() {
  load "$(npm root -g)/bats-support/load.bash"
  load "$(npm root -g)/bats-assert/load.bash"

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"

  # Source the shared library to make _upsert_opencode_plugin available
  source "$PROJECT_ROOT/src/_shared/functions.sh"

  # Isolated temp dir per test (removed in teardown)
  TEST_TEMP="$(mktemp -d)"

  # Check python3 availability for JSON validation
  HAS_PYTHON3=false
  if command -v python3 &>/dev/null; then
    HAS_PYTHON3=true
  fi
}

teardown() {
  rm -rf "$TEST_TEMP"
}

# ── Helpers ──────────────────────────────────────────────────────────────────

# Validate a JSON file is well-formed (python3 required, else skipped).
_assert_valid_json() {
  local file="$1"
  if [[ "$HAS_PYTHON3" != "true" ]]; then
    return 0
  fi
  python3 -c "import json; json.load(open('${file}'))" 2>/dev/null \
    || fail "File is not valid JSON: ${file}"
}

# Assert that a plugin entry exists in a JSON file (python3 required, else
# falls back to grep).
_assert_plugin_entry() {
  local file="$1"
  local entry="$2"
  if [[ "$HAS_PYTHON3" == "true" ]]; then
    python3 -c "
import json
with open('${file}') as f:
    d = json.load(f)
assert '${entry}' in d.get('plugin', []), 'Missing plugin entry: ${entry}'
" 2>/dev/null || fail "Plugin entry '${entry}' missing in ${file}"
  else
    grep -qF "\"${entry}\"" "$file" || fail "Plugin entry '${entry}' missing (grep)"
  fi
}

# Assert that a plugin entry appears exactly N times in the file.
_assert_plugin_entry_count() {
  local file="$1"
  local entry="$2"
  local expected="$3"
  local actual
  actual="$(grep -cF "\"${entry}\"" "$file" || true)"
  [[ "$actual" -eq "$expected" ]] \
    || fail "Expected ${expected} occurrences of '${entry}', got ${actual}"
}

# ── Scenario 7: File not found ──────────────────────────────────────────────

@test "scenario 7: file not found returns exit 1" {
  run _upsert_opencode_plugin "/nonexistent/path/opencode.jsonc" "devbot-plugin"
  assert_failure
  [[ "$status" -eq 1 ]]
  [[ -z "$output" ]]
}

# ── Scenario 5: Minimal file {} ─────────────────────────────────────────────

@test "scenario 5: minimal file '{}' creates plugin array and adds entry" {
  local f="$TEST_TEMP/opencode.jsonc"
  printf '{\n}\n' > "$f"

  run _upsert_opencode_plugin "$f" "only-plugin"
  assert_success
  [[ -z "$output" ]]

  _assert_valid_json "$f"
  _assert_plugin_entry "$f" "only-plugin"
  # Must be the only entry
  _assert_plugin_entry_count "$f" "only-plugin" 1
}

# ── Scenario 2: Add to empty existing array ─────────────────────────────────

@test "scenario 2: add to empty existing plugin array" {
  local f="$TEST_TEMP/opencode.jsonc"
  cat > "$f" <<'EOF'
{
  "plugin": [
  ]
}
EOF

  run _upsert_opencode_plugin "$f" "test-plugin"
  assert_success
  [[ -z "$output" ]]
  _assert_valid_json "$f"
  _assert_plugin_entry "$f" "test-plugin"
}

# ── Scenario 1: Add to non-empty existing array ─────────────────────────────

@test "scenario 1: add to non-empty existing array" {
  local f="$TEST_TEMP/opencode.jsonc"
  cat > "$f" <<'EOF'
{
  "plugin": [
    "opencode-codebase-index"
  ]
}
EOF

  run _upsert_opencode_plugin "$f" "devbot-plugin"
  assert_success
  _assert_valid_json "$f"
  _assert_plugin_entry "$f" "opencode-codebase-index"
  _assert_plugin_entry "$f" "devbot-plugin"
}

# ── Scenario 11: Entry already present in non-empty array ───────────────────

@test "scenario 11: entry already present in non-empty array is no-op" {
  local f="$TEST_TEMP/opencode.jsonc"
  cat > "$f" <<'EOF'
{
  "plugin": [
    "foo",
    "bar"
  ]
}
EOF

  # Snapshot original for byte-exact comparison
  cp "$f" "$f.orig"

  run _upsert_opencode_plugin "$f" "foo"
  assert_success
  [[ -z "$output" ]]

  # File must be byte-identical to original
  diff -q "$f.orig" "$f" || fail "File changed despite entry already present"
  rm -f "$f.orig"

  _assert_valid_json "$f"
  _assert_plugin_entry_count "$f" "foo" 1
}

# ── Scenario 8: Idempotent — same entry twice ────────────────────────────────

@test "scenario 8: adding same entry twice is idempotent" {
  local f="$TEST_TEMP/opencode.jsonc"
  cat > "$f" <<'EOF'
{
  "plugin": [
  ]
}
EOF

  run _upsert_opencode_plugin "$f" "foo"
  assert_success

  run _upsert_opencode_plugin "$f" "foo"
  assert_success

  _assert_valid_json "$f"
  _assert_plugin_entry_count "$f" "foo" 1
}

# ── Scenario 3: Multiple sequential adds ─────────────────────────────────────

@test "scenario 3: multiple sequential adds handle commas correctly" {
  local f="$TEST_TEMP/opencode.jsonc"
  cat > "$f" <<'EOF'
{
  "plugin": [
  ]
}
EOF

  run _upsert_opencode_plugin "$f" "plugin-a"
  assert_success
  _assert_valid_json "$f"

  run _upsert_opencode_plugin "$f" "plugin-b"
  assert_success
  _assert_valid_json "$f"

  _assert_plugin_entry "$f" "plugin-a"
  _assert_plugin_entry "$f" "plugin-b"
  _assert_plugin_entry_count "$f" "plugin-a" 1
  _assert_plugin_entry_count "$f" "plugin-b" 1
}

# ── Scenario 6: {} then add second plugin ────────────────────────────────────

@test "scenario 6: {} then add second plugin (existing array via prior call)" {
  local f="$TEST_TEMP/opencode.jsonc"
  printf '{\n}\n' > "$f"

  run _upsert_opencode_plugin "$f" "first"
  assert_success
  _assert_valid_json "$f"

  run _upsert_opencode_plugin "$f" "second"
  assert_success
  _assert_valid_json "$f"

  _assert_plugin_entry "$f" "first"
  _assert_plugin_entry "$f" "second"
  _assert_plugin_entry_count "$f" "first" 1
  _assert_plugin_entry_count "$f" "second" 1
}

# ── Scenario 4: No plugin section — creates new block ───────────────────────

@test "scenario 4: no plugin section creates new block before closing brace" {
  local f="$TEST_TEMP/opencode.jsonc"
  cat > "$f" <<'EOF'
{
  "agent": {
    "model": "claude-sonnet-4-20250514"
  }
}
EOF

  run _upsert_opencode_plugin "$f" "new-plugin"
  assert_success
  _assert_valid_json "$f"
  _assert_plugin_entry "$f" "new-plugin"

  # Verify the plugin block appears before the closing brace
  grep -qF '"plugin": [' "$f" || fail "Plugin array header missing"
  grep -qF '"new-plugin"' "$f"   || fail "Plugin entry missing"

  # Verify the last field's closing brace gained a trailing comma
  grep -qE '^\s+},$' "$f" \
    || fail "Last field closing brace missing trailing comma"
}

# ── Scenario 10: Full realistic opencode.jsonc layout ────────────────────────

@test "scenario 10: full realistic JSONC layout (no plugin array)" {
  local f="$TEST_TEMP/opencode.jsonc"
  cat > "$f" <<'EOF'
{
  "$schema": "https://opencode-interpreter.com/schema.json",
  "agent": {
    "model": "claude-sonnet-4-20250514"
  },
  "permission": {
    "allow": [
      "bash",
      "read",
      "write"
    ]
  }
}
EOF

  run _upsert_opencode_plugin "$f" "opencode-codebase-index"
  assert_success
  [[ -z "$output" ]]

  # Can't use python3 JSON validation here (JSONC with comments is not valid JSON,
  # and this file has no comments but we keep the convention). Use grep instead.
  grep -qF '"plugin": [' "$f"                 || fail "Plugin array header missing"
  grep -qF '"opencode-codebase-index"' "$f"   || fail "Plugin entry missing"

  # Verify the plugin block is before the final closing brace
  local plugin_line
  local closing_line
  plugin_line="$(grep -nF '"plugin": [' "$f" | head -1 | cut -d: -f1)"
  closing_line="$(grep -n '^}' "$f" | tail -1 | cut -d: -f1)"
  [[ -n "$plugin_line" && -n "$closing_line" ]] || fail "Could not locate lines"
  [[ "$plugin_line" -lt "$closing_line" ]] \
    || fail "Plugin block not before closing brace (line $plugin_line vs $closing_line)"

  # Verify the last field before plugin block has trailing comma
  grep -qF ']' "$f"  # permission closing bracket present
}

# ── Scenario 9: File path entry ──────────────────────────────────────────────

@test "scenario 9: file path entry (dots, slashes) added correctly" {
  local f="$TEST_TEMP/opencode.jsonc"
  cat > "$f" <<'EOF'
{
  "plugin": [
  ]
}
EOF

  run _upsert_opencode_plugin "$f" ".opencode/plugins/devbot/foo.js"
  assert_success
  _assert_valid_json "$f"
  _assert_plugin_entry "$f" ".opencode/plugins/devbot/foo.js"
}

# ── Scenario 12: Special characters (dots, hyphens, slashes) ─────────────────

@test "scenario 12: entry with special characters (dots, hyphens, slashes)" {
  local f="$TEST_TEMP/opencode.jsonc"
  cat > "$f" <<'EOF'
{
  "plugin": [
  ]
}
EOF

  run _upsert_opencode_plugin "$f" "devbot.plugin-v1.0/special"
  assert_success
  _assert_valid_json "$f"
  _assert_plugin_entry "$f" "devbot.plugin-v1.0/special"
}

# ── Edge: Function is silent (no stdout/stderr) ──────────────────────────────

@test "edge: function is silent on success" {
  local f="$TEST_TEMP/opencode.jsonc"
  printf '{\n}\n' > "$f"

  run _upsert_opencode_plugin "$f" "silent-test"
  assert_success
  [[ -z "$output" ]] || fail "Expected silent operation, got output: $output"
}

# ── Edge: trailing comma for multi-field JSON ────────────────────────────────

@test "edge: trailing comma added when file has multiple root fields" {
  local f="$TEST_TEMP/opencode.jsonc"
  cat > "$f" <<'EOF'
{
  "field_a": "value_a",
  "field_b": "value_b"
}
EOF

  run _upsert_opencode_plugin "$f" "test-entry"
  assert_success
  _assert_valid_json "$f"
  _assert_plugin_entry "$f" "test-entry"

  # field_b should now have a trailing comma
  grep -qF '"field_b": "value_b",' "$f" \
    || fail "Last field before plugin block missing trailing comma"
}
