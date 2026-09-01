#!/usr/bin/env bats
# =============================================================================
# src/agentic/memory/tests/memory-smoke_tests.bats
# Smoke tests for init.sh scaffolding and skill file integrity.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  FIXTURES="$TEST_DIR/fixtures"
}

teardown() {
  # Clean up any temp files/dirs left by test failures (early assertion exits)
  find "$FIXTURES" -maxdepth 1 -name 'tmp.*' -exec rm -rf {} + 2>/dev/null || true
}

# ── init.sh scaffold ──────────────────────────────────────────────────────────

@test "init.sh: scaffolds full vault directory structure" {
  local tmpdir
  tmpdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"

  run bash "$MODULE_DIR/init.sh" "$tmpdir"

  assert_success
  assert_output --partial "Vault scaffolded"

  # Verify core directories exist
  local vault="$tmpdir/.agents/memory"
  [[ -d "$vault/latent/PDRs"       ]] || fail "latent/PDRs/ missing"
  [[ -d "$vault/latent/ADRs"       ]] || fail "latent/ADRs/ missing"
  [[ -d "$vault/latent/learnings"    ]] || fail "latent/learnings/ missing"
  [[ -d "$vault/latent/global"     ]] || fail "latent/global/ missing"
  [[ -d "$vault/work/active"       ]] || fail "work/active/ missing"
  [[ -d "$vault/work/archive"      ]] || fail "work/archive/ missing"
  [[ -d "$vault/reference"         ]] || fail "reference/ missing"
  [[ -d "$vault/thinking"          ]] || fail "thinking/ missing"
  [[ -d "$vault/active"           ]] || fail "active/ missing"

  # Verify .gitkeep files
  [[ -f "$vault/work/active/.gitkeep"  ]] || fail "work/active/.gitkeep missing"
  [[ -f "$vault/work/archive/.gitkeep" ]] || fail "work/archive/.gitkeep missing"
  [[ -f "$vault/reference/.gitkeep"    ]] || fail "reference/.gitkeep missing"
  [[ -f "$vault/thinking/.gitkeep"     ]] || fail "thinking/.gitkeep missing"

  # Verify .git/info/exclude was created
  local exclude="$tmpdir/.git/info/exclude"
  [[ -f "$exclude" ]] || fail ".git/info/exclude not created"
  grep -qF "# >>> DEVBOT - memory" "$exclude" || fail "Missing DEVBOT section in .git/info/exclude"

  rm -rf "$tmpdir"
}

@test "init.sh: idempotent — re-running does not error" {
  local tmpdir
  tmpdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"

  # First run
  run bash "$MODULE_DIR/init.sh" "$tmpdir"
  assert_success

  # Second run — should not error
  run bash "$MODULE_DIR/init.sh" "$tmpdir"
  assert_success

  rm -rf "$tmpdir"
}

# ── audit-25 F6: global memory store wiring ───────────────────────────────────
# The global store was unreachable on a fresh macOS install: no
# .agents/memory/latent/global symlink and no QMD collection. The scaffold
# code exists, but no test asserted the symlink TARGET or the collection
# registration — the old -d check dereferences the symlink and passes even
# when the target is wrong or missing.

@test "init.sh: latent/global symlink points at the dev-bot central store" {
  local tmpdir
  tmpdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"

  run bash "$MODULE_DIR/init.sh" "$tmpdir"
  assert_success

  local link="$tmpdir/.agents/memory/latent/global"
  [[ -L "$link" ]] || fail "latent/global is not a symlink"
  local expected
  expected="$(cd "$MODULE_DIR/../../../storage/global-memories" && pwd)"
  local actual
  actual="$(readlink "$link")"
  [[ "$actual" == "$expected" ]] \
    || fail "latent/global -> $actual (expected $expected)"

  # The target must actually exist — a dangling symlink is a silent failure.
  [[ -d "$expected" ]] || fail "global store target missing: $expected"
  [[ -d "$link" ]] || fail "latent/global does not resolve to a directory"

  rm -rf "$tmpdir"
}

@test "init.sh: re-run preserves the global symlink (idempotent)" {
  local tmpdir
  tmpdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"

  run bash "$MODULE_DIR/init.sh" "$tmpdir"
  assert_success
  run bash "$MODULE_DIR/init.sh" "$tmpdir"
  assert_success

  local link="$tmpdir/.agents/memory/latent/global"
  [[ -L "$link" ]] || fail "latent/global is not a symlink after re-run"
  local expected
  expected="$(cd "$MODULE_DIR/../../../storage/global-memories" && pwd)"
  local actual
  actual="$(readlink "$link")"
  [[ "$actual" == "$expected" ]] || fail "symlink target changed on re-run"

  rm -rf "$tmpdir"
}

@test "init.sh: registers the dev-bot-global QMD collection when qmd is available" {
  command -v qmd &>/dev/null || skip "qmd not installed"

  local tmpdir
  tmpdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"

  run bash "$MODULE_DIR/init.sh" "$tmpdir"
  assert_success

  run qmd collection show dev-bot-global
  assert_success

  rm -rf "$tmpdir"
}

@test "init.sh: warns (not silently succeeds) when qmd collection add fails" {
  # Stub qmd to fail: the collection must be registered with the shared name
  # dev-bot-global; a stub that always fails must surface a warning, not a
  # silent success (the old '&& _ok' swallowed the error).
  local stubdir
  stubdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$stubdir/qmd" <<'SCRIPT'
#!/usr/bin/env bash
exit 1
SCRIPT
  chmod +x "$stubdir/qmd"

  local tmpdir
  tmpdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"

  run env PATH="$stubdir:$PATH" bash "$MODULE_DIR/init.sh" "$tmpdir"
  assert_success
  assert_output --partial "WARN"
  assert_output --partial "dev-bot-global"

  rm -rf "$tmpdir" "$stubdir"
}

@test "init.sh: reinit does not clobber per-project active files" {
  local tmpdir
  tmpdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"

  run bash "$MODULE_DIR/init.sh" "$tmpdir"
  assert_success

  # Simulate per-project content (create-project-report / generate-mcp-guide output)
  local manifest="$tmpdir/.agents/memory/active/preemptive-skill-loading-list.md"
  echo "- devbot:custom-project-skill" >> "$manifest"

  run bash "$MODULE_DIR/init.sh" "$tmpdir"
  assert_success

  # The scaffold must NOT have overwritten the curated manifest with the
  # template default (audit-22: a reinit silently reverted a curated fixture).
  run grep -q "devbot:custom-project-skill" "$manifest"
  assert_success

  rm -rf "$tmpdir"
}

@test "init.sh: creates .git/info/exclude with DEVBOT memory section" {
  local tmpdir
  tmpdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"

  run bash "$MODULE_DIR/init.sh" "$tmpdir"

  assert_success
  assert_output --partial ".git/info/exclude"

  local exclude="$tmpdir/.git/info/exclude"
  [[ -f "$exclude" ]] || fail ".git/info/exclude not created"

  grep -qF "# >>> DEVBOT - memory" "$exclude" || fail "Missing DEVBOT start marker"
  grep -qF ".agents/memory/thinking" "$exclude" || fail "Missing thinking/ entry"
  grep -qF ".agents/memory/work" "$exclude" || fail "Missing work/ entry"
  grep -qF "# <<< DEVBOT - memory" "$exclude" || fail "Missing DEVBOT end marker"

  rm -rf "$tmpdir"
}

@test "init.sh: .git/info/exclude is idempotent — re-running replaces section cleanly" {
  local tmpdir
  tmpdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"

  # First run creates .git/info/exclude with one DEVBOT section
  run bash "$MODULE_DIR/init.sh" "$tmpdir"
  assert_success

  # Verify exactly one section after first run
  local count1
  count1="$(grep -c "# >>> DEVBOT - memory" "$tmpdir/.git/info/exclude" 2>/dev/null || echo 0)"
  [[ "$count1" -eq 1 ]] || fail "Expected 1 DEVBOT section after first run, got $count1"

  # Second run — should replace (not duplicate)
  run bash "$MODULE_DIR/init.sh" "$tmpdir"
  assert_success
  assert_output --partial ".git/info/exclude updated"

  # Count DEVBOT markers after second run — should still be exactly 1
  local count2
  count2="$(grep -c "# >>> DEVBOT - memory" "$tmpdir/.git/info/exclude" 2>/dev/null || echo 0)"
  [[ "$count2" -eq 1 ]] || fail "DEVBOT section was duplicated (expected 1, got $count2)"

  rm -rf "$tmpdir"
}

@test "init.sh: appends to existing .git/info/exclude without removing existing content" {
  local tmpdir
  tmpdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"

  # Pre-populate .git/info/exclude with existing content
  mkdir -p "$tmpdir/.git/info"
  echo "vendor/" > "$tmpdir/.git/info/exclude"
  echo "node_modules/" >> "$tmpdir/.git/info/exclude"

  run bash "$MODULE_DIR/init.sh" "$tmpdir"
  assert_success

  # Original entries preserved
  grep -q "^vendor/$" "$tmpdir/.git/info/exclude" || fail "Original vendor/ entry lost"
  grep -q "^node_modules/$" "$tmpdir/.git/info/exclude" || fail "Original node_modules/ entry lost"

  # New DEVBOT section added
  grep -qF "# >>> DEVBOT - memory" "$tmpdir/.git/info/exclude" || fail "DEVBOT section not appended"

  rm -rf "$tmpdir"
}

# ── Skill file validation ─────────────────────────────────────────────────────

@test "skill files: exactly 5 SKILL.md files exist" {
  local count
  count="$(find "$MODULE_DIR/skills" -name 'SKILL.md' -type f | wc -l)"
  # Count the number of skill subdirectories containing SKILL.md
  local dirs
  dirs="$(find "$MODULE_DIR/skills" -name 'SKILL.md' -type f -exec dirname {} \; | wc -l)"
  [[ "$dirs" -eq 5 ]] || fail "Expected 5 skill subdirectories with SKILL.md, found $dirs"
}

@test "skill files: all SKILL.md files are non-empty" {
  local files
  files="$(find "$MODULE_DIR/skills" -name 'SKILL.md' -type f)"
  for f in $files; do
    local size
    size="$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null)"
    [[ "$size" -gt 0 ]] || fail "Empty file: $f"
  done
}

@test "skill files: all SKILL.md files start with valid YAML frontmatter (---)" {
  local files
  files="$(find "$MODULE_DIR/skills" -name 'SKILL.md' -type f)"
  for f in $files; do
    local first_line
    first_line="$(head -1 "$f")"
    [[ "$first_line" == "---" ]] || fail "Missing YAML frontmatter delimiter in $f (first line: $first_line)"
  done
}

@test "skill files: all SKILL.md have a name field in frontmatter" {
  local files
  files="$(find "$MODULE_DIR/skills" -name 'SKILL.md' -type f)"
  for f in $files; do
    grep -q '^name:' "$f" || fail "Missing 'name:' field in $f"
  done
}

@test "skill files: all SKILL.md have a description field in frontmatter" {
  local files
  files="$(find "$MODULE_DIR/skills" -name 'SKILL.md' -type f)"
  for f in $files; do
    grep -q '^description:' "$f" || fail "Missing 'description:' field in $f"
  done
}
