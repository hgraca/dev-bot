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

@test "single file: expands compact JSON to indented" {
  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.json)"
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
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.json)"
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
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.json)"
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
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.json)"
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
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.jsonc)"
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
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.jsonc)"
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
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.jsonc)"
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
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.jsonc)"
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
  tmpdir="$(mktemp -d "$BATS_TEST_TMPDIR/tmpdir.XXXXXX")"
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
  tmpdir="$(mktemp -d "$BATS_TEST_TMPDIR/tmpdir.XXXXXX")"
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
  tmp1="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.json)"
  tmp2="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.json)"
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

@test "non-existent file: warns and exits 0 (vanished-file race)" {
  # file.edited can fire for a path renamed or deleted before the hook runs.
  # There is nothing to format — a warning, never a failure.
  run bash "$TOOL" "$FIXTURES/does_not_exist.json"

  assert_success
  assert_output --partial "WARN"
}

# ── Edge cases ─────────────────────────────────────────────────────────────────

@test "empty file: no crash, clean exit" {
  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.json)"
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
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.json)"
  printf '{invalid}\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_failure
  assert_output --partial "Error"

  rm -f "$tmpfile"
}

@test "file with crlf line endings: no crash, formatted correctly" {
  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.json)"
  printf '{"a":1,"b":2}\r\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"
  assert_success

  run cat "$tmpfile"
  assert_output --partial "\"a\": 1"

  rm -f "$tmpfile"
}

@test "non-json extension: ignored in directory mode" {
  local tmpdir
  tmpdir="$(mktemp -d "$BATS_TEST_TMPDIR/tmpdir.XXXXXX")"
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
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.json)"
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
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.json)"
  printf '{"a": 1}\n' > "$tmpfile"

  export PATH="$sb:$PATH"
  run bash "$TOOL" "$tmpfile"
  assert_output --partial "WARN:"

  run cat "$tmpfile"
  assert_output --partial '"a": 1'
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
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.json)"
  printf '{"a": 1}\n' > "$tmpfile"

  export PATH="$sb:$PATH"
  run bash "$TOOL" "$tmpfile"
  assert_success
  assert_output --partial "WARN"
  [ ! -f "$tmpfile" ]
}

# ── prettier config resolution ────────────────────────────────────────────────

@test "no prettier config in the project: formats with dev-bot's default config" {
  local project
  project="$(mktemp -d)"
  local tmpfile="$project/tmp.json"
  printf '{"a":1}\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"

  assert_success
  run cat "$tmpfile"
  assert_output --partial '"a": 1'
}

@test "no prettier config in the project: --check reports instead of exiting 2" {
  # The reported failure: the prettier gate turned a check into exit 2.
  local project
  project="$(mktemp -d)"
  local tmpfile="$project/tmp.json"
  printf '{"a":1}\n' > "$tmpfile"

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
  tmpfile="$project/tmp.json"
  printf '{"a":1}\n' > "$tmpfile"

  PATH="$sb:$PATH" bash "$TOOL" "$tmpfile"
  run head -n 1 "$argv"
  assert_output --partial "prettier.default.json"

  # A declared config is prettier's to resolve; we must not pass one.
  printf '{}\n' > "$project/.prettierrc.json"
  PATH="$sb:$PATH" bash "$TOOL" "$tmpfile"
  run tail -n 1 "$argv"
  refute_output --partial "prettier.default.json"
}

@test "--force: still accepted so existing callers keep working" {
  # `devbot reinit` passes --force; it must stay accepted (not be taken for a
  # path) even though formatting no longer depends on a project config.
  local project
  project="$(mktemp -d)"
  local tmpfile="$project/tmp.json"
  printf '{"a":1}\n' > "$tmpfile"

  run bash -c "cd '${project}' && bash '${TOOL}' --force '${tmpfile}'"

  assert_success
  refute_output --partial "not a file or directory"
  run cat "$tmpfile"
  assert_output --partial '"a": 1'
}

@test "no prettier on PATH: warns, exits 0, and leaves the file untouched" {
  local sb="$BATS_TEST_TMPDIR/stub-noprettier"
  mkdir -p "$sb"
  ln -sf "$(command -v python3)" "$sb/python3"
  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.json)"
  printf '{"a":1}\n' > "$tmpfile"

  run env PATH="$sb" python3 "$MODULE_DIR/tools/format-json.py" "$tmpfile"

  assert_success
  # The specific message: a missing prettier binary otherwise surfaces as the
  # vanished-file warning (FileNotFoundError) — also "WARN" and exit 0.
  assert_output --partial "prettier (or node) not found"
  run cat "$tmpfile"
  assert_output --partial '"a":1'
}

@test "pipe mode: passes input through with a warning when prettier is missing" {
  # A formatter that cannot run must not swallow a pipe.
  local sb="$BATS_TEST_TMPDIR/stub-noprettier-pipe"
  mkdir -p "$sb"
  ln -sf "$(command -v python3)" "$sb/python3"
  local input="$BATS_TEST_TMPDIR/pipe-in.json"
  printf '{"a":1}\n' > "$input"

  run env PATH="$sb" python3 "$MODULE_DIR/tools/format-json.py" < "$input"

  assert_success
  assert_output --partial "prettier (or node) not found"
  assert_output --partial '"a":1'
}

@test "single file: reports how many files changed" {
  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.json)"
  printf '{"a":1}\n' > "$tmpfile"

  run bash "$TOOL" "$tmpfile"

  assert_success
  assert_output --partial "format-json: 1 file(s) checked, 1 changed"
}

@test "--check: exits 1 and lists a file that needs formatting" {
  local tmpfile
  tmpfile="$(mktemp -p "$BATS_TEST_TMPDIR" tmp.XXXXXX.json)"
  printf '{"a":1}\n' > "$tmpfile"

  run bash "$TOOL" --check "$tmpfile"

  assert_failure
  assert_output --partial "$tmpfile"
  assert_output --partial "1 need formatting"
  run cat "$tmpfile"
  assert_output --partial '{"a":1}'
}

@test "directory: a batch formatting failure makes the run fail" {
  local dir="$BATS_TEST_TMPDIR/batch-bad"
  mkdir -p "$dir"
  printf '{invalid}\n' > "$dir/bad.json"

  run bash "$TOOL" "$dir"

  assert_failure
  assert_output --partial "Error"
}

@test "--check missing file: exits 1 instead of a false green" {
  run bash "$TOOL" --check "$BATS_TEST_TMPDIR/missing.json"

  assert_failure
  assert_output --partial "is not a file or directory"
  assert_output --partial "0 file(s) checked"
}

# ── Project ignore rules ──────────────────────────────────────────────────────

@test "prettierignore: an ignored file is left untouched" {
  mkdir -p "$BATS_TEST_TMPDIR/project"
  printf '{}\n' > "$BATS_TEST_TMPDIR/project/.prettierrc.json"
  printf '/*\n!/src/\n!/src/**\n' > "$BATS_TEST_TMPDIR/project/.prettierignore"
  mkdir -p "$BATS_TEST_TMPDIR/project/config"
  local ignored="$BATS_TEST_TMPDIR/project/config/ignored.json"
  printf '{"a":   1}\n' > "$ignored"

  run bash "$TOOL" "$ignored"

  assert_success
  assert_output --partial "0 changed"
  run cat "$ignored"
  assert_output --partial '{"a":   1}'
}

@test "prettierignore: a re-included file is still formatted" {
  mkdir -p "$BATS_TEST_TMPDIR/project"
  printf '{}\n' > "$BATS_TEST_TMPDIR/project/.prettierrc.json"
  printf '/*\n!/src/\n!/src/**\n' > "$BATS_TEST_TMPDIR/project/.prettierignore"
  mkdir -p "$BATS_TEST_TMPDIR/project/src"
  local target="$BATS_TEST_TMPDIR/project/src/a.json"
  printf '{"b":   2}\n' > "$target"

  run bash "$TOOL" "$target"

  assert_success
  assert_output --partial "1 changed"
  run cat "$target"
  assert_output --partial '{ "b": 2 }'
}

@test "prettierignore: --check passes for an ignored file" {
  mkdir -p "$BATS_TEST_TMPDIR/project"
  printf '{}\n' > "$BATS_TEST_TMPDIR/project/.prettierrc.json"
  printf '/*\n!/src/\n!/src/**\n' > "$BATS_TEST_TMPDIR/project/.prettierignore"
  mkdir -p "$BATS_TEST_TMPDIR/project/config"
  local ignored="$BATS_TEST_TMPDIR/project/config/ignored.json"
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
  local note="$BATS_TEST_TMPDIR/project/.agents/memory/n.json"
  printf '{"c":   3}\n' > "$note"

  run bash "$TOOL" "$note"

  assert_success
  assert_output --partial "1 changed"
  run cat "$note"
  assert_output --partial '{ "c": 3 }'
}

@test "ignore rules: a .gitignore entry does not stop formatting" {
  mkdir -p "$BATS_TEST_TMPDIR/project"
  printf '{}\n' > "$BATS_TEST_TMPDIR/project/.prettierrc.json"
  printf 'out/\n' > "$BATS_TEST_TMPDIR/project/.gitignore"
  mkdir -p "$BATS_TEST_TMPDIR/project/out"
  local target="$BATS_TEST_TMPDIR/project/out/x.json"
  printf '{"d":   4}\n' > "$target"

  run bash "$TOOL" "$target"

  assert_success
  assert_output --partial "1 changed"
  run cat "$target"
  assert_output --partial '{ "d": 4 }'
}
