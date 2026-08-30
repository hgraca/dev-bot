#!/usr/bin/env bats
# =============================================================================
# src/agentic/format-json/tests/format-json_tests.bats
# Tests for the format-json bash entrypoint.
# Tests from the bash entrypoint, covering all options and outputs.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="$MODULE_DIR/tools/format-json.mcp.sh"
  FIXTURES="$TEST_DIR/fixtures"

  command -v python3 &>/dev/null || skip "python3 not installed"
  command -v node &>/dev/null || skip "node not installed"
}

# ── Help flag ─────────────────────────────────────────────────────────────────

@test "--help: prints usage and exits 0" {
  run bash "$TOOL" --help

  assert_success
  assert_output --partial "Usage:"
}

# ── Single file ────────────────────────────────────────────────────────────────

@test "single file: expands compact JSON to indented" {
  local tmpfile
  tmpfile="$(mktemp -p "$FIXTURES" tmp.XXXXXX.json)"
  printf '{"name":"test","value":42}\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"

  assert_success
  run cat "$tmpfile"
  assert_output --partial "\"name\": \"test\""
  assert_output --partial "\"value\": 42"

  rm -f "$tmpfile"
}

@test "single file: nested objects are indented correctly" {
  local tmpfile
  tmpfile="$(mktemp -p "$FIXTURES" tmp.XXXXXX.json)"
  printf '{"a":{"b":{"c":1}}}\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  run cat "$tmpfile"
  assert_output --partial "\"a\": {"
  assert_output --partial "\"b\": {"
  assert_output --partial "\"c\": 1"

  rm -f "$tmpfile"
}

@test "single file: already formatted file is unchanged (no-op)" {
  local tmpfile
  tmpfile="$(mktemp -p "$FIXTURES" tmp.XXXXXX.json)"
  printf '{\n  "a": 1\n}\n' > "$tmpfile"
  local before
  before="$(cat "$tmpfile")"

  run bash "$TOOL" "$tmpfile"
  assert_success

  local after
  after="$(cat "$tmpfile")"
  [[ "$before" == "$after" ]]
  rm -f "$tmpfile"
}

@test "single file: arrays are formatted" {
  local tmpfile
  tmpfile="$(mktemp -p "$FIXTURES" tmp.XXXXXX.json)"
  printf '{"items":[1,2,3]}\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  run cat "$tmpfile"
  assert_output --partial "1,"
  assert_output --partial "2,"
  assert_output --partial "3"

  rm -f "$tmpfile"
}

# ── JSONC support ──────────────────────────────────────────────────────────────

@test "jsonc single file: preserves line comments" {
  local tmpfile
  tmpfile="$(mktemp -p "$FIXTURES" tmp.XXXXXX.jsonc)"
  printf '{\n  // This is a comment\n  "name": "test"\n}\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  run cat "$tmpfile"
  # Comments should be preserved (prettier handles JSONC natively)
  assert_output --partial "\"name\": \"test\""
  assert_output --partial "// This is a comment"

  rm -f "$tmpfile"
}

@test "jsonc single file: preserves block comments" {
  local tmpfile
  tmpfile="$(mktemp -p "$FIXTURES" tmp.XXXXXX.jsonc)"
  printf '{\n  /* block comment */\n  "value": 42\n}\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  run cat "$tmpfile"
  assert_output --partial "\"value\": 42"
  assert_output --partial "/* block comment */"

  rm -f "$tmpfile"
}

@test "jsonc single file: trailing commas are stripped" {
  local tmpfile
  tmpfile="$(mktemp -p "$FIXTURES" tmp.XXXXXX.jsonc)"
  printf '{\n  "a": 1,\n  "b": 2,\n}\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  run cat "$tmpfile"
  # Should not have the trailing comma
  refute grep -q '"b": 2,' <<< "$output"

  rm -f "$tmpfile"
}

@test "jsonc single file: comments inside strings are preserved" {
  local tmpfile
  tmpfile="$(mktemp -p "$FIXTURES" tmp.XXXXXX.jsonc)"
  printf '{\n  "path": "http://example.com/foo"\n}\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  run cat "$tmpfile"
  assert_output --partial "http://example.com/foo"

  rm -f "$tmpfile"
}

# ── Directory mode ─────────────────────────────────────────────────────────────

@test "directory: formats all .json files recursively" {
  local tmpdir
  tmpdir="$(mktemp -d "$FIXTURES/tmpdir.XXXXXX")"
  mkdir -p "$tmpdir/sub"
  printf '{"a":1}\n' > "$tmpdir/file.json"
  printf '{"b":2}\n' > "$tmpdir/sub/nested.json"

  run bash "$TOOL" "$tmpdir"
  assert_success

  run cat "$tmpdir/file.json"
  assert_output --partial "\"a\": 1"

  run cat "$tmpdir/sub/nested.json"
  assert_output --partial "\"b\": 2"

  rm -rf "$tmpdir"
}

@test "directory: formats .jsonc files too" {
  local tmpdir
  tmpdir="$(mktemp -d "$FIXTURES/tmpdir.XXXXXX")"
  printf '{"a":1}\n' > "$tmpdir/config.jsonc"

  run bash "$TOOL" "$tmpdir"
  assert_success

  run cat "$tmpdir/config.jsonc"
  assert_output --partial "\"a\": 1"

  rm -rf "$tmpdir"
}

# ── Multiple files ─────────────────────────────────────────────────────────────

@test "multiple files: formats each in-place" {
  local tmp1 tmp2
  tmp1="$(mktemp -p "$FIXTURES" tmp.XXXXXX.json)"
  tmp2="$(mktemp -p "$FIXTURES" tmp.XXXXXX.json)"
  printf '{"a":1}\n' > "$tmp1"
  printf '{"b":2}\n' > "$tmp2"

  run bash "$TOOL" "$tmp1" "$tmp2"
  assert_success

  run cat "$tmp1"
  assert_output --partial "\"a\": 1"

  run cat "$tmp2"
  assert_output --partial "\"b\": 2"

  rm -f "$tmp1" "$tmp2"
}

# ── Pipe mode ──────────────────────────────────────────────────────────────────

@test "pipe mode: reads from stdin, writes formatted to stdout" {
  run bash -c 'printf "{\"a\":1,\"b\":2}\n" | bash "$0"' "$TOOL"

  assert_success
  assert_output --partial "\"a\": 1"
  assert_output --partial "\"b\": 2"
}

@test "pipe mode: nested objects are indented" {
  run bash -c 'printf "{\"a\":{\"b\":1}}\n" | bash "$0"' "$TOOL"

  assert_success
  assert_output --partial "\"a\": {"
  assert_output --partial "\"b\": 1"
}

# ── Non-existent file ──────────────────────────────────────────────────────────

@test "non-existent file: prints error to stderr" {
  run bash "$TOOL" "$FIXTURES/does_not_exist.json"

  assert_failure
  assert_output --partial "Error"
}

# ── Edge cases ─────────────────────────────────────────────────────────────────

@test "empty file: no crash, clean exit" {
  local tmpfile
  tmpfile="$(mktemp -p "$FIXTURES" tmp.XXXXXX.json)"
  touch "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  # File should remain empty
  run cat "$tmpfile"
  [[ -z "$output" ]]

  rm -f "$tmpfile"
}

@test "invalid JSON: prints parse error" {
  local tmpfile
  tmpfile="$(mktemp -p "$FIXTURES" tmp.XXXXXX.json)"
  printf '{invalid}\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_failure
  assert_output --partial "Error"

  rm -f "$tmpfile"
}

@test "file with crlf line endings: no crash, formatted correctly" {
  local tmpfile
  tmpfile="$(mktemp -p "$FIXTURES" tmp.XXXXXX.json)"
  printf '{"a":1,"b":2}\r\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  run cat "$tmpfile"
  assert_output --partial "\"a\": 1"

  rm -f "$tmpfile"
}

@test "non-json extension: ignored in directory mode" {
  local tmpdir
  tmpdir="$(mktemp -d "$FIXTURES/tmpdir.XXXXXX")"
  printf '{"a":1}\n' > "$tmpdir/config.json"
  printf 'not json at all\n' > "$tmpdir/config.txt"

  run bash "$TOOL" "$tmpdir"
  assert_success

  # .txt should be untouched
  run cat "$tmpdir/config.txt"
  assert_output --partial "not json at all"

  # .json should be formatted
  run cat "$tmpdir/config.json"
  assert_output --partial "\"a\": 1"

  rm -rf "$tmpdir"
}

@test "larger json: preserves key ordering" {
  local tmpfile
  tmpfile="$(mktemp -p "$FIXTURES" tmp.XXXXXX.json)"
  printf '{"z":1,"a":2,"m":3}\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  run cat "$tmpfile"
  # Order should be preserved (sort_keys=False in json.dumps)
  local first_key
  first_key="$(grep -o '"[a-z]"' <<< "$output" | head -1)"
  [[ "$first_key" == '"z"' ]]

  rm -f "$tmpfile"
}
