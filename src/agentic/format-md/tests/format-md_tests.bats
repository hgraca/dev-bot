#!/usr/bin/env bats
# =============================================================================
# src/agentic/format-md/tests/format-md_tests.bats
# Tests for the format-md bash entrypoint (via prettier).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="$MODULE_DIR/tools/format-md.mcp.sh"
  FIXTURES="$TEST_DIR/fixtures"

  command -v python3 &>/dev/null || skip "python3 not installed"
  command -v node &>/dev/null || skip "node not installed"

  # The tool formats only a project that declares prettier, so the fixtures
  # declare it — without this every formatting assertion below would pass
  # vacuously (an untouched file still contains "a" and "b").
  mkdir -p "$BATS_TEST_TMPDIR"
  printf '{}\n' > "$BATS_TEST_TMPDIR/.prettierrc.json"
}

# ── Help flag ─────────────────────────────────────────────────────────────────

@test "--help: prints usage and exits 0" {
  run bash "$TOOL" --help

  assert_success
  assert_output --partial "Usage:"
}

# ── Single file ────────────────────────────────────────────────────────────────

@test "single file: formats table content" {
  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.md)"
  printf '| a | b |\n| --- | --- |\n| 1 | 2 |\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"

  assert_success
  run cat "$tmpfile"
  assert_output --partial "a"
  assert_output --partial "b"
  # Prettier padded the cells: this is what proves the file really was formatted,
  # where the bare content assertions above pass either way.
  assert_output --partial "| 1   | 2   |"

  rm -f "$tmpfile"
}

@test "single file: handles headings and text" {
  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.md)"
  printf '# Heading\n\nSome text.\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  run cat "$tmpfile"
  assert_output --partial "# Heading"
  assert_output --partial "Some text"

  rm -f "$tmpfile"
}

@test "single file: preserves code fences" {
  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.md)"
  printf '# Example\n\n```\ncode block\n```\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  run cat "$tmpfile"
  assert_output --partial '```'
  assert_output --partial "code block"

  rm -f "$tmpfile"
}

# ── Directory mode ─────────────────────────────────────────────────────────────

@test "directory: formats all .md files recursively" {
  local tmpdir
  tmpdir="$(mktemp -d "$BATS_TEST_TMPDIR/tmpdir.XXXXXX")"
  mkdir -p "$tmpdir/sub"
  printf '| x | y |\n| --- | --- |\n| 1 | 2 |\n' > "$tmpdir/file1.md"
  printf '# no table\n' > "$tmpdir/sub/file2.md"

  run bash "$TOOL" "$tmpdir"
  assert_success

  run cat "$tmpdir/file1.md"
  assert_output --partial "x"
  assert_output --partial "y"

  run cat "$tmpdir/sub/file2.md"
  assert_output --partial "# no table"

  rm -rf "$tmpdir"
}

# ── Multiple files ─────────────────────────────────────────────────────────────

@test "multiple files: formats each in-place" {
  local tmp1 tmp2
  tmp1="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.md)"
  tmp2="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.md)"
  printf '| a | b |\n| --- | --- |\n| 1 | 2 |\n' > "$tmp1"
  printf '| c | d |\n| --- | --- |\n| 3 | 4 |\n' > "$tmp2"

  run bash "$TOOL" "$tmp1" "$tmp2"
  assert_success

  run cat "$tmp1"
  assert_output --partial "a"
  assert_output --partial "b"

  run cat "$tmp2"
  assert_output --partial "c"
  assert_output --partial "d"

  rm -f "$tmp1" "$tmp2"
}

# ── Pipe mode ─────────────────────────────────────────────────────────────────

@test "pipe mode: reads from stdin, writes formatted to stdout" {
  run bash -c 'printf "| a | b |\n| --- | --- |\n| 1 | 2 |\n" | bash "$0"' "$TOOL"

  assert_success
  assert_output --partial "a"
  assert_output --partial "b"
}

# ── Non-existent file ──────────────────────────────────────────────────────────

@test "non-existent file: warns and exits 0 (vanished-file race)" {
  # file.edited can fire for a path renamed or deleted before the hook runs.
  # There is nothing to format — a warning, never a failure.
  run bash "$TOOL" "$FIXTURES/does_not_exist.md"

  assert_success
  assert_output --partial "WARN"
}

# ── Edge cases ─────────────────────────────────────────────────────────────────

@test "empty file: no crash, clean exit" {
  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.md)"
  touch "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  rm -f "$tmpfile"
}

@test "table with colon-aligned separator preserved" {
  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.md)"
  printf '| a | b | c |\n| :-- | :-: | --: |\n| 1 | 2 | 3 |\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  run cat "$tmpfile"
  assert_output --partial "a"
  assert_output --partial "b"
  assert_output --partial "c"

  rm -f "$tmpfile"
}

@test "non-md file extension: ignored in directory mode" {
  local tmpdir
  tmpdir="$(mktemp -d "$BATS_TEST_TMPDIR/tmpdir.XXXXXX")"
  printf '| a | b |\n| --- | --- |\n| 1 | 2 |\n' > "$tmpdir/file.txt"
  printf '| a | b |\n| --- | --- |\n| 1 | 2 |\n' > "$tmpdir/file.md"

  run bash "$TOOL" "$tmpdir"
  assert_success

  # .txt should be untouched (no formatting at all)
  run cat "$tmpdir/file.txt"
  assert_output --partial "| --- | --- |"

  # .md should be formatted
  run cat "$tmpdir/file.md"
  assert_output --partial "a"
  assert_output --partial "b"

  rm -rf "$tmpdir"
}

@test "file with crlf line endings: no crash, content preserved" {
  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.md)"
  printf '| a | b |\r\n| --- | --- |\r\n| 1 | 2 |\r\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  run cat "$tmpfile"
  assert_output --partial "a"
  assert_output --partial "b"

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
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.md)"
  printf '# Title\n' > "$tmpfile"

  export PATH="$sb:$PATH"
  run bash "$TOOL" "$tmpfile"
  assert_output --partial "WARN:"

  run cat "$tmpfile"
  assert_output --partial "# Title"
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
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.md)"
  printf '# Title\n' > "$tmpfile"

  export PATH="$sb:$PATH"
  run bash "$TOOL" "$tmpfile"
  assert_success
  assert_output --partial "WARN"
  [ ! -f "$tmpfile" ]
}

# ── prettier gate ─────────────────────────────────────────────────────────────

@test "no prettier config in the project: the file is left untouched" {
  # Prettier is not every project's formatter. One that never declares it must
  # not have its files rewritten to a standard it did not adopt.
  local project
  project="$(mktemp -d)"
  local tmpfile="$project/tmp.md"
  printf '| longheader | b |\n|---|---|\n|1|2|\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"

  assert_success
  run cat "$tmpfile"
  # Still unpadded: prettier would have widened the separator row.
  assert_output --partial "|---|---|"
}

@test "no prettier on PATH: warns, exits 0, and leaves the file untouched" {
  # Never fatal — the file.edited hook must not fail an edit.
  local sb="$BATS_TEST_TMPDIR/stub-noprettier"
  mkdir -p "$sb"
  ln -sf "$(command -v python3)" "$sb/python3"
  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.md)"
  printf '| longheader | b |\n|---|---|\n|1|2|\n' > "$tmpfile"

  # The python tool is called directly: the .mcp.sh wrapper needs readlink and
  # dirname, which the stripped PATH does not provide.
  run env PATH="$sb" python3 "$MODULE_DIR/tools/format-md.py" "$tmpfile"

  assert_success
  # The specific message: a missing prettier binary otherwise surfaces as the
  # vanished-file warning (FileNotFoundError), which looks identical to a
  # "WARN + exit 0" assertion.
  assert_output --partial "prettier (or node) not found"
  run cat "$tmpfile"
  assert_output --partial "|---|---|"
}

@test "pipe mode: passes input through with a warning when prettier is missing" {
  # A formatter that cannot run must not swallow a pipe.
  local sb="$BATS_TEST_TMPDIR/stub-noprettier-pipe"
  mkdir -p "$sb"
  ln -sf "$(command -v python3)" "$sb/python3"
  local input="$BATS_TEST_TMPDIR/pipe-in.md"
  printf '| longheader | b |\n|---|---|\n|1|2|\n' > "$input"

  run env PATH="$sb" python3 "$MODULE_DIR/tools/format-md.py" < "$input"

  assert_success
  assert_output --partial "prettier (or node) not found"
  assert_output --partial "longheader"
}
