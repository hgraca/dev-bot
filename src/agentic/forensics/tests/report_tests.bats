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

# An ISO-8601 UTC stamp `days` in the past — keeps fixtures relative to the run.
_ago() {
  python3 -c 'import datetime, sys; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%S+00:00"))' "$1"
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

@test "report --format html: carries the data-quality block and the analysis placeholder" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  _mined "$repo" "$db"

  run bash "${TOOL}" report "$db" --format html --with-analysis
  assert_success
  assert_output --partial "<h2>Data quality</h2>"
  assert_output --partial "Analysis &amp; recommendations"
  assert_output --partial "Refactoring targets"
}

@test "report --format html: states an absent commit activity rather than dropping it" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  printf 'a\n' >"$repo/a.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "feat: a"
  # --all records no window, so there is no commit activity to report.
  bash "${TOOL}" mine "$repo" --db "$db" --granularity file --all >/dev/null

  run bash "${TOOL}" report "$db" --format html
  assert_success
  assert_output --partial "Commit activity"
  assert_output --partial "unavailable"
}

@test "report: embeds the commit activity section" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  _mined "$repo" "$db"

  run bash "${TOOL}" report "$db"
  assert_success
  assert_output --partial "## Commit activity"
}

@test "report: Commit activity shares the committer-dated window" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  printf 'a\n' >"$repo/a.txt"
  git -C "$repo" add -A
  # Authored 2024, committed yesterday: inside the window by committer date only,
  # so an author-dated activity section would disagree with Commit process.
  GIT_AUTHOR_DATE="2024-01-01T10:00:00+00:00" GIT_COMMITTER_DATE="$(_ago 1)" \
    git -C "$repo" commit -q -m "feat: backdated"
  bash "${TOOL}" mine "$repo" --db "$db" --granularity file >/dev/null

  run bash "${TOOL}" report "$db" --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
process = doc["process"][0]["commits"]
activity = doc["commit-activity"][0]["commits"]
assert process == activity, (process, activity)
'

  rm -rf "$repo"
}

@test "report --with-prs: no github origin degrades to a note, not a failure" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  _mined "$repo" "$db"

  run bash "${TOOL}" report "$db" --with-prs
  assert_success
  assert_output --partial "## Pull request activity"
  assert_output --partial "unavailable"
}

@test "report --with-prs: a partial provider fetch is stated, not hidden" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  _mined "$repo" "$db"

  run env FORENSICS_SOURCES_DIR="${TEST_DIR}/fixtures/sources-github-partial" \
    bash "${TOOL}" report "$db" --with-prs
  assert_success
  assert_output --partial "## Pull request activity"
  assert_output --partial "partial: some pages failed"
}

@test "report --with-prs: a corrupt PR cache degrades, never tracebacks" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  _mined "$repo" "$db"
  mkdir -p "${repo}/.forensics"
  printf 'not a sqlite database' >"${repo}/.forensics/prs.sqlite"

  run bash "${TOOL}" report "$db" --with-prs
  assert_success
  assert_output --partial "## Pull request activity"
  refute_output --partial "Traceback"
}

@test "run: mines and writes one complete report in a single step" {
  local repo work out
  repo="$(mktemp -d)"
  work="$(mktemp -d)"
  out="${work}/r.md"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  printf 'a\n' >"$repo/a.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "feat TP-1: add a"

  run bash "${TOOL}" run "$repo" --granularity file --out "$out"
  assert_success
  assert [ -f "$out" ]
  # Exactly the one file: no report.html / mine.json / activity-*.md siblings.
  assert [ "$(ls "${work}" | wc -l)" -eq 1 ]

  run cat "$out"
  assert_output --partial "## Data quality"
  assert_output --partial "## Commit activity"
  assert_output --partial "## Analysis & recommendations"
  assert_output --partial "TP-1"
}
