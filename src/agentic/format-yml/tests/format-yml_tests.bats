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
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.yml)"
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
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.yml)"
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
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.yml)"
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
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.yml)"
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
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.yaml)"
  printf 'name: test\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  rm -f "$tmpfile"
}

# ── Comments preserved ─────────────────────────────────────────────────────────

@test "comments: line comments are preserved" {
  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.yml)"
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
  tmpdir="$(mktemp -d "$BATS_TEST_TMPDIR/tmpdir.XXXXXX")"
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
  tmpdir="$(mktemp -d "$BATS_TEST_TMPDIR/tmpdir.XXXXXX")"
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
  tmp1="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.yml)"
  tmp2="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.yml)"
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

@test "non-existent file: warns and exits 0 (vanished-file race)" {
  # file.edited can fire for a path renamed or deleted before the hook runs.
  # There is nothing to format — a warning, never a failure.
  run bash "$TOOL" "$FIXTURES/does_not_exist.yml"

  assert_success
  assert_output --partial "WARN"
}

# ── Edge cases ─────────────────────────────────────────────────────────────────

@test "empty file: no crash, clean exit" {
  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.yml)"
  touch "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  rm -f "$tmpfile"
}

@test "invalid YAML: prints parse error" {
  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.yml)"
  printf '{invalid yaml\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_failure
  assert_output --partial "Error"

  rm -f "$tmpfile"
}

@test "non-yaml extension: ignored in directory mode" {
  local tmpdir
  tmpdir="$(mktemp -d "$BATS_TEST_TMPDIR/tmpdir.XXXXXX")"
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
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.yml)"
  printf 'z: 1\na: 2\nm: 3\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  run cat "$tmpfile"
  local first_key
  first_key="$(grep -o '^[a-z]' <<< "$output" | head -1)"
  [[ "$first_key" == "z" ]]

  rm -f "$tmpfile"
}

# ── Concurrent-write safety ───────────────────────────────────────────────────

@test "single file: a change landing while prettier runs is not overwritten" {
  # The file.edited hook runs this tool, so a format run can overlap the agent's
  # next edit. The stub prettier simulates exactly that: it writes to the file
  # mid-run, then returns a "formatted" result the tool used to write back —
  # silently discarding the newer content.
  local sb="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$sb"

  printf '#!/usr/bin/env bash\nexit 0\n' > "$sb/node"
  cat > "$sb/prettier" <<'STUB'
#!/usr/bin/env bash
path=""
prev=""
for a in "$@"; do
  [[ "$prev" == "--stdin-filepath" ]] && path="$a"
  prev="$a"
done
[[ -n "$path" ]] && printf 'concurrent write\n' >> "$path"
cat
printf '\n'
STUB
  chmod +x "$sb/node" "$sb/prettier"

  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.yml)"
  printf 'a: 1\n' > "$tmpfile"

  export PATH="$sb:$PATH"
  run bash "$TOOL" "$tmpfile"
  assert_output --partial "WARN:"

  run cat "$tmpfile"
  assert_output --partial 'a: 1'
  assert_output --partial "concurrent write"

  rm -f "$tmpfile"
}

@test "single file: a file deleted while prettier runs warns and exits 0" {
  # The other half of the vanished-file race: the path passed the isfile()
  # check and is gone by the time the formatted result is written back.
  local sb="$BATS_TEST_TMPDIR/stub-del"
  mkdir -p "$sb"

  printf '#!/usr/bin/env bash\nexit 0\n' > "$sb/node"
  cat > "$sb/prettier" <<'STUB'
#!/usr/bin/env bash
path=""
prev=""
for a in "$@"; do
  [[ "$prev" == "--stdin-filepath" ]] && path="$a"
  prev="$a"
done
[[ -n "$path" ]] && rm -f "$path"
cat
printf '\n'
STUB
  chmod +x "$sb/node" "$sb/prettier"

  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.yml)"
  printf 'a: 1\n' > "$tmpfile"

  export PATH="$sb:$PATH"
  run bash "$TOOL" "$tmpfile"
  assert_success
  assert_output --partial "WARN"
  [ ! -f "$tmpfile" ]
}
