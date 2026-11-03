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

  # Declare prettier so the formatting assertions below exercise the project's
  # own configuration; the no-config fallback has its own tests.
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

# ── prettier config resolution ────────────────────────────────────────────────

@test "no prettier config in the project: formats with dev-bot's default config" {
  # A project that never declares prettier must still be formattable; the run
  # uses the defaults dev-bot ships rather than skipping the file.
  local project
  project="$(mktemp -d)"
  local tmpfile="$project/tmp.md"
  printf '| longheader | b |\n|---|---|\n|1|2|\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"

  assert_success
  run cat "$tmpfile"
  # Padded to the header width, which only the default config's table formatting does.
  assert_output --partial "| longheader | b   |"
}

@test "no prettier config in the project: --check reports instead of exiting 2" {
  # The reported failure: the prettier gate turned a check into exit 2.
  local project
  project="$(mktemp -d)"
  local tmpfile="$project/tmp.md"
  printf '| a | b |\n|---|---|\n|1|2|\n' > "$tmpfile"

  run bash "$TOOL" --check "$tmpfile"

  assert_failure 1
  assert_output --partial "$tmpfile"
}

@test "the default config is passed to prettier only when the project declares none" {
  # `{}` is byte-identical to prettier's own defaults, so the formatted output
  # cannot prove the fallback ran — assert on prettier's argv instead.
  local sb="$BATS_TEST_TMPDIR/stub-argv"
  local argv="$BATS_TEST_TMPDIR/prettier.argv"
  mkdir -p "$sb"
  : > "$argv"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\ncat\n' "$argv" > "$sb/prettier"
  chmod +x "$sb/prettier"
  ln -sf "$(command -v node)" "$sb/node"

  local project tmpfile
  project="$(mktemp -d)"
  tmpfile="$project/tmp.md"
  printf '# Title\n' > "$tmpfile"

  PATH="$sb:$PATH" bash "$TOOL" "$tmpfile"
  run head -n 1 "$argv"
  assert_output --partial "prettier.default.json"

  # A declared config is prettier's to resolve; we must not pass one.
  printf '{}\n' > "$project/.prettierrc.json"
  PATH="$sb:$PATH" bash "$TOOL" "$tmpfile"
  run tail -n 1 "$argv"
  refute_output --partial "prettier.default.json"
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

# ── Change reporting and --check ──────────────────────────────────────────────

@test "single file: reports how many files changed" {
  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.md)"
  printf '| a | b |\n| --- | --- |\n| 1 | 2 |\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"

  assert_success
  assert_output --partial "format-md: 1 file(s) checked, 1 changed"
}

@test "single file: reports zero changed when already formatted" {
  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.md)"
  printf '| a | b |\n| --- | --- |\n| 1 | 2 |\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  run bash "$TOOL" "$tmpfile"

  assert_success
  assert_output --partial "format-md: 1 file(s) checked, 0 changed"
}

@test "--check: exits 1 and lists a file that needs formatting" {
  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.md)"
  printf '| a | b |\n| --- | --- |\n| 1 | 2 |\n' > "$tmpfile"

  run bash "$TOOL" --check "$tmpfile"

  assert_failure
  assert_output --partial "$tmpfile"
  assert_output --partial "1 need formatting"
  # It must report, not rewrite.
  run cat "$tmpfile"
  assert_output --partial '| 1 | 2 |'
}

@test "--check: exits 0 when the file is already formatted" {
  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.md)"
  printf '| a | b |\n| --- | --- |\n| 1 | 2 |\n' > "$tmpfile"

  bash "$TOOL" "$tmpfile" >/dev/null
  run bash "$TOOL" --check "$tmpfile"

  assert_success
  assert_output --partial "0 need formatting"
}

@test "--check without a path: usage error" {
  run bash "$TOOL" --check

  assert_failure
  assert_output --partial "--check requires at least one path"
}

@test "--check with no prettier on PATH: exits 2 instead of a false green" {
  local sb="$BATS_TEST_TMPDIR/stub-noprettier-check"
  mkdir -p "$sb"
  ln -sf "$(command -v python3)" "$sb/python3"
  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.md)"
  printf '# Heading\n' > "$tmpfile"

  run env PATH="$sb" python3 "$MODULE_DIR/tools/format-md.py" --check "$tmpfile"

  assert_failure
  assert_output --partial "cannot verify formatting"
}

@test "--check missing file: exits 1 instead of a false green" {
  run bash "$TOOL" --check "$BATS_TEST_TMPDIR/missing.md"

  assert_failure
  assert_output --partial "is not a file or directory"
  assert_output --partial "0 file(s) checked"
}

@test "--check detects CRLF that the writer would normalize" {
  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.md)"
  printf '# Heading\r\n\r\nSome text.\r\n' > "$tmpfile"

  run bash "$TOOL" --check "$tmpfile"
  assert_failure
  assert_output --partial "1 need formatting"

  bash "$TOOL" "$tmpfile" >/dev/null
  run bash "$TOOL" --check "$tmpfile"
  assert_success
  assert_output --partial "0 need formatting"
}

@test "--check respects an explicit CRLF formatter configuration" {
  local dir="$BATS_TEST_TMPDIR/crlf-config"
  mkdir -p "$dir"
  printf '{"endOfLine":"crlf"}\n' > "$dir/.prettierrc.json"
  printf '# Heading\r\n\r\nSome text.\r\n' > "$dir/a.md"

  run bash "$TOOL" --check "$dir/a.md"
  assert_success
  assert_output --partial "0 need formatting"

  run bash "$TOOL" "$dir/a.md"
  assert_success
  run bash "$TOOL" --check "$dir/a.md"
  assert_success
  assert_output --partial "0 need formatting"
}

@test "directory write: an embedded code fence is left alone, like single-file mode" {
  # prettier formats fenced code by default; the hook turns that off for single
  # files and --check, so a directory run must not rewrite a fence either.
  local dir="$BATS_TEST_TMPDIR/embedded-fence"
  mkdir -p "${dir}"
  printf '```js\nconst x = {a:1};\n```\n' > "${dir}/doc.md"

  run bash "$TOOL" "${dir}"

  assert_success
  run cat "${dir}/doc.md"
  assert_output --partial "const x = {a:1};"
}


# ── Project ignore rules ──────────────────────────────────────────────────────

@test "prettierignore: an ignored file is left untouched" {
  mkdir -p "$BATS_TEST_TMPDIR/project"
  printf '{}\n' > "$BATS_TEST_TMPDIR/project/.prettierrc.json"
  printf '/*\n!/src/\n!/src/**\n' > "$BATS_TEST_TMPDIR/project/.prettierignore"
  mkdir -p "$BATS_TEST_TMPDIR/project/docs"
  local ignored="$BATS_TEST_TMPDIR/project/docs/ignored.md"
  printf '#    Title\n' > "$ignored"

  run bash "$TOOL" "$ignored"

  assert_success
  assert_output --partial "0 changed"
  run cat "$ignored"
  assert_output --partial "#    Title"
}

@test "prettierignore: a re-included file is still formatted" {
  mkdir -p "$BATS_TEST_TMPDIR/project"
  printf '{}\n' > "$BATS_TEST_TMPDIR/project/.prettierrc.json"
  printf '/*\n!/src/\n!/src/**\n' > "$BATS_TEST_TMPDIR/project/.prettierignore"
  mkdir -p "$BATS_TEST_TMPDIR/project/src"
  local target="$BATS_TEST_TMPDIR/project/src/a.md"
  printf '#    Sub\n' > "$target"

  run bash "$TOOL" "$target"

  assert_success
  assert_output --partial "1 changed"
  run cat "$target"
  assert_output --partial "# Sub"
}

@test "prettierignore: --check passes for an ignored file" {
  mkdir -p "$BATS_TEST_TMPDIR/project"
  printf '{}\n' > "$BATS_TEST_TMPDIR/project/.prettierrc.json"
  printf '/*\n!/src/\n!/src/**\n' > "$BATS_TEST_TMPDIR/project/.prettierignore"
  mkdir -p "$BATS_TEST_TMPDIR/project/docs"
  local ignored="$BATS_TEST_TMPDIR/project/docs/ignored.md"
  printf 'name:    x\n' > "$ignored"

  run bash "$TOOL" --check "$ignored"

  assert_success
  assert_output --partial "0 need formatting"
}

@test "ignore rules: the .agents workspace is exempt from .prettierignore" {
  mkdir -p "$BATS_TEST_TMPDIR/project"
  printf '{}\n' > "$BATS_TEST_TMPDIR/project/.prettierrc.json"
  printf '/*\n' > "$BATS_TEST_TMPDIR/project/.prettierignore"
  printf '{"devbot_dir": ".agents"}\n' > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc"
  mkdir -p "$BATS_TEST_TMPDIR/project/.agents/memory"
  local note="$BATS_TEST_TMPDIR/project/.agents/memory/n.md"
  printf '#    Note\n' > "$note"

  run bash "$TOOL" "$note"

  assert_success
  assert_output --partial "1 changed"
  run cat "$note"
  assert_output --partial "# Note"
}

@test "ignore rules: a .gitignore entry does not stop formatting" {
  mkdir -p "$BATS_TEST_TMPDIR/project"
  printf '{}\n' > "$BATS_TEST_TMPDIR/project/.prettierrc.json"
  printf 'out/\n' > "$BATS_TEST_TMPDIR/project/.gitignore"
  mkdir -p "$BATS_TEST_TMPDIR/project/out"
  local target="$BATS_TEST_TMPDIR/project/out/x.md"
  printf '#    Git\n' > "$target"

  run bash "$TOOL" "$target"

  assert_success
  assert_output --partial "1 changed"
  run cat "$target"
  assert_output --partial "# Git"
}
