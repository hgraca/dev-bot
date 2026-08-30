#!/usr/bin/env bats
# =============================================================================
# src/agentic/format-yml/tests/format-yml_tests.bats
# Tests for the format-yml bash entrypoint.
# Tests from the bash entrypoint, covering all options and outputs.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="$MODULE_DIR/tools/format-yml.mcp.sh"
  FIXTURES="$TEST_DIR/fixtures"
  mkdir -p "$FIXTURES"

  command -v python3 &>/dev/null || skip "python3 not installed"
  command -v node &>/dev/null || skip "node not installed"
  command -v npx &>/dev/null || skip "npx not installed"
}

# ── Help flag ─────────────────────────────────────────────────────────────────

@test "--help: prints usage and exits 0" {
  run bash "$TOOL" --help

  assert_success
  assert_output --partial "Usage:"
}

# ── Single file ────────────────────────────────────────────────────────────────

@test "single file: expands compact YAML to 2-space indented" {
  local tmpfile
  tmpfile="$(mktemp -p "$FIXTURES" tmp.XXXXXX.yml)"
  printf 'name: test\nvalue: 42\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"

  assert_success
  run cat "$tmpfile"
  assert_output --partial "name: test"
  assert_output --partial "value: 42"

  rm -f "$tmpfile"
}

@test "single file: nested mappings are indented correctly" {
  local tmpfile
  tmpfile="$(mktemp -p "$FIXTURES" tmp.XXXXXX.yml)"
  printf 'a:\n  b:\n    c: 1\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  run cat "$tmpfile"
  assert_output --partial "a:"
  assert_output --partial "  b:"
  assert_output --partial "    c: 1"

  rm -f "$tmpfile"
}

@test "single file: already formatted file is unchanged (no-op)" {
  local tmpfile
  tmpfile="$(mktemp -p "$FIXTURES" tmp.XXXXXX.yml)"
  printf 'name: test\nvalue: 42\n' > "$tmpfile"
  local before
  before="$(cat "$tmpfile")"

  run bash "$TOOL" "$tmpfile"
  assert_success

  local after
  after="$(cat "$tmpfile")"
  [[ "$before" == "$after" ]]
  rm -f "$tmpfile"
}

@test "single file: sequences are formatted" {
  local tmpfile
  tmpfile="$(mktemp -p "$FIXTURES" tmp.XXXXXX.yml)"
  printf 'items:\n  - 1\n  - 2\n  - 3\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  run cat "$tmpfile"
  assert_output --partial "- 1"
  assert_output --partial "- 2"
  assert_output --partial "- 3"

  rm -f "$tmpfile"
}

@test "single file: .yaml extension works" {
  local tmpfile
  tmpfile="$(mktemp -p "$FIXTURES" tmp.XXXXXX.yaml)"
  printf 'name: test\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  rm -f "$tmpfile"
}

# ── Comments preserved ─────────────────────────────────────────────────────────

@test "comments: line comments are preserved" {
  local tmpfile
  tmpfile="$(mktemp -p "$FIXTURES" tmp.XXXXXX.yml)"
  printf '# This is a comment\nname: test\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  run cat "$tmpfile"
  assert_output --partial "# This is a comment"
  assert_output --partial "name: test"

  rm -f "$tmpfile"
}

# ── Directory mode ─────────────────────────────────────────────────────────────

@test "directory: formats all .yml files recursively" {
  local tmpdir
  tmpdir="$(mktemp -d "$FIXTURES/tmpdir.XXXXXX")"
  mkdir -p "$tmpdir/sub"
  printf 'a: 1\n' > "$tmpdir/file.yml"
  printf 'b: 2\n' > "$tmpdir/sub/nested.yml"

  run bash "$TOOL" "$tmpdir"
  assert_success

  run cat "$tmpdir/file.yml"
  assert_output --partial "a: 1"

  run cat "$tmpdir/sub/nested.yml"
  assert_output --partial "b: 2"

  rm -rf "$tmpdir"
}

@test "directory: formats .yaml files too" {
  local tmpdir
  tmpdir="$(mktemp -d "$FIXTURES/tmpdir.XXXXXX")"
  printf 'a: 1\n' > "$tmpdir/config.yaml"

  run bash "$TOOL" "$tmpdir"
  assert_success

  run cat "$tmpdir/config.yaml"
  assert_output --partial "a: 1"

  rm -rf "$tmpdir"
}

# ── Multiple files ─────────────────────────────────────────────────────────────

@test "multiple files: formats each in-place" {
  local tmp1 tmp2
  tmp1="$(mktemp -p "$FIXTURES" tmp.XXXXXX.yml)"
  tmp2="$(mktemp -p "$FIXTURES" tmp.XXXXXX.yml)"
  printf 'a: 1\n' > "$tmp1"
  printf 'b: 2\n' > "$tmp2"

  run bash "$TOOL" "$tmp1" "$tmp2"
  assert_success

  run cat "$tmp1"
  assert_output --partial "a: 1"

  run cat "$tmp2"
  assert_output --partial "b: 2"

  rm -f "$tmp1" "$tmp2"
}

# ── Pipe mode ──────────────────────────────────────────────────────────────────

@test "pipe mode: reads from stdin, writes formatted to stdout" {
  run bash -c 'printf "a: 1\nb: 2\n" | bash "$0"' "$TOOL"

  assert_success
  assert_output --partial "a: 1"
  assert_output --partial "b: 2"
}

# ── Non-existent file ──────────────────────────────────────────────────────────

@test "non-existent file: prints error to stderr" {
  run bash "$TOOL" "$FIXTURES/does_not_exist.yml"

  assert_failure
  assert_output --partial "Error"
}

# ── Edge cases ─────────────────────────────────────────────────────────────────

@test "empty file: no crash, clean exit" {
  local tmpfile
  tmpfile="$(mktemp -p "$FIXTURES" tmp.XXXXXX.yml)"
  touch "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  rm -f "$tmpfile"
}

@test "invalid YAML: prints parse error" {
  local tmpfile
  tmpfile="$(mktemp -p "$FIXTURES" tmp.XXXXXX.yml)"
  printf '{invalid yaml\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_failure
  assert_output --partial "Error"

  rm -f "$tmpfile"
}

@test "non-yaml extension: ignored in directory mode" {
  local tmpdir
  tmpdir="$(mktemp -d "$FIXTURES/tmpdir.XXXXXX")"
  printf 'a: 1\n' > "$tmpdir/config.yml"
  printf 'not yaml\n' > "$tmpdir/config.txt"

  run bash "$TOOL" "$tmpdir"
  assert_success

  # .txt should be untouched
  run cat "$tmpdir/config.txt"
  assert_output --partial "not yaml"

  # .yml should be formatted
  run cat "$tmpdir/config.yml"
  assert_output --partial "a: 1"

  rm -rf "$tmpdir"
}

@test "key ordering: preserved after formatting" {
  local tmpfile
  tmpfile="$(mktemp -p "$FIXTURES" tmp.XXXXXX.yml)"
  printf 'z: 1\na: 2\nm: 3\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  run cat "$tmpfile"
  local first_key
  first_key="$(grep -o '^[a-z]' <<< "$output" | head -1)"
  [[ "$first_key" == "z" ]]

  rm -f "$tmpfile"
}
