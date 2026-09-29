#!/usr/bin/env bats
# =============================================================================
# src/agentic/forensics/tests/report_tests.bats
# The report command surface: single-file output, and the analysis placeholder
# an agent fills in.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="${MODULE_DIR}/tools/forensics.sh"
}

# A minimal repository plus its store.
_mined() {
  local repo="$1" db="$2"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  printf 'a\n' >"$repo/a.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "feat: a"
  bash "${TOOL}" mine "$repo" --db "$db" --granularity file >/dev/null
}

@test "report --out: a .md path is the file, a directory keeps report.md" {
  local repo db work
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  work="$(mktemp -d)"
  _mined "$repo" "$db"

  run bash "${TOOL}" report "$db" --out "${work}/one.md"
  assert_success
  assert [ -f "${work}/one.md" ]

  run bash "${TOOL}" report "$db" --out "${work}/dir"
  assert_success
  assert [ -f "${work}/dir/report.md" ]
}

@test "report --with-analysis: emits the placeholder an agent fills in" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  _mined "$repo" "$db"

  run bash "${TOOL}" report "$db" --with-analysis
  assert_success
  assert_output --partial "## Analysis & recommendations"
  assert_output --partial "### Refactoring targets"
  assert_output --partial "### Bus factor & knowledge sharing"
}

@test "report: omits the analysis placeholder unless asked" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  _mined "$repo" "$db"

  run bash "${TOOL}" report "$db"
  assert_success
  refute_output --partial "## Analysis & recommendations"
}
