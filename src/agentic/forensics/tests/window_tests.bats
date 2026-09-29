#!/usr/bin/env bats
# =============================================================================
# src/agentic/forensics/tests/window_tests.bats
# Time-window binding: the default window, --all, windowed releases,
# trend-engine error surfacing and the report's ownership-anchor note.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="${MODULE_DIR}/tools/forensics.sh"
  PHP_PLUGIN="${MODULE_DIR}/langs/php/plugin.sh"
}

# An ISO-8601 UTC stamp `days` in the past — keeps the in-window fixture relative
# to the run instead of a hardcoded date that rots.
_ago() {
  python3 -c 'import datetime, sys; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%S+00:00"))' "$1"
}

# True when the PHP plugin can run for real (docker + a resolvable engine).
_php_ready() {
  command -v docker >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1 || return 1
  bash "${PHP_PLUGIN}" doctor --project "$1" >/dev/null 2>&1
}

# One commit far outside the default window and one inside it, each carrying an
# annotated release tag dated to its own commit.
_build_aged_repo() {
  local dir="$1" old_date="2024-01-01T10:00:00+00:00" recent_date
  recent_date="$(_ago 2)"

  git -C "$dir" init -q
  git -C "$dir" config user.name "Alice"
  git -C "$dir" config user.email "alice@example.com"
  git -C "$dir" config commit.gpgsign false

  printf 'a\n' >"${dir}/a.txt"
  git -C "$dir" add a.txt
  GIT_AUTHOR_DATE="${old_date}" GIT_COMMITTER_DATE="${old_date}" \
    git -C "$dir" commit -q -m "feat: old"
  GIT_COMMITTER_DATE="${old_date}" git -C "$dir" tag -a old-release -m "old release"

  printf 'a\nb\n' >"${dir}/a.txt"
  git -C "$dir" add a.txt
  GIT_AUTHOR_DATE="${recent_date}" GIT_COMMITTER_DATE="${recent_date}" \
    git -C "$dir" commit -q -m "fix: recent"
  git -C "$dir" tag -a recent-release -m "recent release"
}

@test "mine: defaults to the last month, excluding older commits" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  _build_aged_repo "$repo"

  run bash "${TOOL}" mine "$repo" --db "$db" --granularity file --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
counts = json.load(sys.stdin)["counts"]
assert counts["commits"] == 1, counts
'

  rm -rf "$repo"
}

@test "mine --all: mines the whole history past the default window" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  _build_aged_repo "$repo"

  run bash "${TOOL}" mine "$repo" --db "$db" --granularity file --all --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
counts = json.load(sys.stdin)["counts"]
assert counts["commits"] == 2, counts
'

  rm -rf "$repo"
}

@test "mine: records the resolved window in the store meta" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  _build_aged_repo "$repo"

  run bash "${TOOL}" mine "$repo" --db "$db" --granularity file --format json
  assert_success

  run python3 -c "
import sqlite3
meta = dict(sqlite3.connect('${db}').execute('SELECT key, value FROM meta').fetchall())
assert meta['since'], meta
assert meta['until'], meta
assert meta['since'] < meta['until'], meta
"
  assert_success

  rm -rf "$repo"
}

@test "mine --all: records an empty, unbounded window in the store meta" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  _build_aged_repo "$repo"

  run bash "${TOOL}" mine "$repo" --db "$db" --granularity file --all --format json
  assert_success

  run python3 -c "
import sqlite3
meta = dict(sqlite3.connect('${db}').execute('SELECT key, value FROM meta').fetchall())
assert meta['since'] == '', meta
assert meta['until'] == '', meta
"
  assert_success

  rm -rf "$repo"
}

@test "mine: a reversed window is an ERROR, not a silent empty mine" {
  local repo
  repo="$(mktemp -d)"
  _build_aged_repo "$repo"

  run bash "${TOOL}" mine "$repo" --db "$(mktemp -d)/d.sqlite" --granularity file \
    --since 2026-09-25 --until 2026-09-21 --format json
  assert_failure
  assert_output --partial "ERROR"

  rm -rf "$repo"
}

@test "analyse releases: a bounded mine excludes tags from outside the window" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  _build_aged_repo "$repo"

  run bash "${TOOL}" mine "$repo" --db "$db" --granularity file --format json
  assert_success
  run bash "${TOOL}" analyse "$db" --view releases --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
tags = {row["tag"] for row in json.load(sys.stdin)["releases"]}
assert tags == {"recent-release"}, tags
'

  run bash "${TOOL}" mine "$repo" --db "$db" --granularity file --all --format json
  assert_success
  run bash "${TOOL}" analyse "$db" --view releases --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
tags = {row["tag"] for row in json.load(sys.stdin)["releases"]}
assert tags == {"old-release", "recent-release"}, tags
'

  rm -rf "$repo"
}

@test "mine --trends: a failing engine at a sampled revision is a WARN, not silence" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  printf 'x\n' >"$repo/a.zz"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2024-01-01T10:00:00+00:00" GIT_COMMITTER_DATE="2024-01-01T10:00:00+00:00" \
    git -C "$repo" commit -q -m "feat: zz"

  run env FORENSICS_LANGS_DIR="${TEST_DIR}/fixtures/langs-multi" \
    bash "${TOOL}" mine "$repo" --db "$db" --granularity file --trends --all --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert any(w.startswith("trends: ") and "boom" in w for w in doc["warnings"]), doc["warnings"]
assert doc["counts"]["complexity_trend"] >= 1, doc["counts"]
'

  rm -rf "$repo"
}

@test "report: states the mining window and the unit-ownership anchor" {
  local repo db out
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  out="$(mktemp -d)"
  _build_aged_repo "$repo"

  run bash "${TOOL}" mine "$repo" --db "$db" --granularity file --format json
  assert_success
  run bash "${TOOL}" report "$db" --out "$out" --format md
  assert_success

  run cat "${out}/report.md"
  assert_success
  assert_output --partial "unit ownership anchored at:"
  assert_output --partial "Every metric is bound to the mining window"

  rm -rf "$repo"
}

@test "mine unit-ownership: anchors attribution at the window's end date" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  git -C "$repo" init -q
  git -C "$repo" config commit.gpgsign false

  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  printf '<?php\nclass A {\n  public function a() { return 1; }\n}\n' >"$repo/A.php"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2026-09-01T10:00:00+00:00" GIT_COMMITTER_DATE="2026-09-01T10:00:00+00:00" \
    git -C "$repo" commit -q -m "feat: add a"

  git -C "$repo" config user.name "Bob"
  git -C "$repo" config user.email "bob@example.com"
  printf '<?php\nclass A {\n  public function a() { return 1; }\n  public function b() { return 2; }\n}\n' >"$repo/A.php"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2026-09-10T10:00:00+00:00" GIT_COMMITTER_DATE="2026-09-10T10:00:00+00:00" \
    git -C "$repo" commit -q -m "feat: add b"

  _php_ready "$repo" || skip "php engine + docker not available"

  # The anchor falls between the two commits: b() did not exist then, so it is
  # not attributed — only a() survives.
  run bash "${TOOL}" mine "$repo" --db "$db" --since 2026-09-01 --until 2026-09-05 --format json
  assert_success
  run bash "${TOOL}" analyse "$db" --view unit-ownership --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
names = {row["name"] for row in json.load(sys.stdin)["unit-ownership"]}
assert "A::a" in names, names
assert "A::b" not in names, names
'

  rm -rf "$repo"
}

@test "mine: --all combined with an explicit bound is an ERROR, not a silent override" {
  local repo
  repo="$(mktemp -d)"
  _build_aged_repo "$repo"

  run bash "${TOOL}" mine "$repo" --db "$(mktemp -d)/d.sqlite" --granularity file \
    --all --since 2026-09-01 --format json
  assert_failure
  assert_output --partial "ERROR"
  assert_output --partial "--all"

  rm -rf "$repo"
}

@test "--all: is rejected outside mine rather than silently ignored" {
  run bash "${TOOL}" commits --all
  assert_failure
  assert_output --partial "--all is only supported by mine"
}

@test "mine: selects on committer date, unlike the commits activity command" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  printf 'a\n' >"$repo/a.txt"
  git -C "$repo" add -A
  # Authored long ago, committed yesterday: inside a committer-date window, outside
  # an author-date one. The mined store and `commits` therefore differ by design.
  GIT_AUTHOR_DATE="2024-01-01T10:00:00+00:00" GIT_COMMITTER_DATE="$(_ago 1)" \
    git -C "$repo" commit -q -m "feat: backdated"

  run bash "${TOOL}" mine "$repo" --db "$db" --granularity file --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
assert json.load(sys.stdin)["counts"]["commits"] == 1, "mine is committer-dated"
'

  run bash "${TOOL}" commits "$repo" --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
assert json.load(sys.stdin)["total"]["commits"] == 0, "commits is author-dated"
'

  rm -rf "$repo"
}

@test "mine: file dates follow the committer date, matching the selection window" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  printf 'a\n' >"$repo/a.txt"
  git -C "$repo" add -A
  # Authored 2024, committed yesterday: the window selects it on the committer
  # date, so the dates it reports must be the committer ones, not 2024.
  GIT_AUTHOR_DATE="2024-01-01T10:00:00+00:00" GIT_COMMITTER_DATE="$(_ago 1)" \
    git -C "$repo" commit -q -m "feat: backdated"

  run bash "${TOOL}" mine "$repo" --db "$db" --granularity file
  assert_success

  run bash "${TOOL}" analyse "$db" --view change-rate --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
rows = [r for r in json.load(sys.stdin)["change-rate"] if r["path"] == "a.txt"]
assert rows, "no change-rate row for a.txt"
assert not (rows[0]["first_seen"] or "").startswith("2024"), rows[0]
assert not (rows[0]["last_seen"] or "").startswith("2024"), rows[0]
'

  run bash "${TOOL}" analyse "$db" --view process --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
row = json.load(sys.stdin)["process"][0]
assert row["active_days"] == 1, row
'

  rm -rf "$repo"
}

@test "mine trends: buckets on committer date, so one committer day is one sample" {
  local repo db same_day
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  same_day="$(_ago 2)"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  printf 'x\n' >"$repo/a.zz"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2024-01-01T10:00:00+00:00" GIT_COMMITTER_DATE="${same_day}" \
    git -C "$repo" commit -q -m "feat: one"
  printf 'x\ny\n' >"$repo/a.zz"
  git -C "$repo" add -A
  # Same committer day, a different author day: one bucket keyed on committer date,
  # two keyed on author date.
  GIT_AUTHOR_DATE="2025-06-01T10:00:00+00:00" GIT_COMMITTER_DATE="${same_day}" \
    git -C "$repo" commit -q -m "feat: two"

  run env FORENSICS_LANGS_DIR="${TEST_DIR}/fixtures/langs-multi" \
    bash "${TOOL}" mine "$repo" --db "$db" --granularity file --trends --trend-interval day \
    --all --format json
  assert_success
  run bash "${TOOL}" analyse "$db" --view trends --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
rows = [r for r in json.load(sys.stdin)["trends"] if r["path"] == "a.zz"]
assert rows, "no trend row for a.zz"
assert rows[0]["snapshots"] == 1, rows
'

  rm -rf "$repo"
}

@test "mine: warns when a requested source yields nothing, instead of going silent" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  # A .txt file no language plugin owns, committed as a fix with no parent to
  # blame: unit extraction and the SZZ link both come back empty.
  printf 'x\n' >"$repo/notes.txt"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="$(_ago 2)" GIT_COMMITTER_DATE="$(_ago 2)" \
    git -C "$repo" commit -q -m "fix: notes"

  run bash "${TOOL}" mine "$repo" --db "$db" --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
warnings = json.load(sys.stdin)["warnings"]
assert any("no units extracted" in w for w in warnings), warnings
assert any("no defect link" in w for w in warnings), warnings
'

  rm -rf "$repo"
}

@test "mine trends: the default interval over a short window warns instead of going silent" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/d.sqlite"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  printf 'if a\n' >"$repo/code.zz"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="$(_ago 2)" GIT_COMMITTER_DATE="$(_ago 2)" \
    git -C "$repo" commit -q -m "feat: zz"

  # Default window (one calendar month) + default interval (month) = one bucket.
  run env FORENSICS_LANGS_DIR="${TEST_DIR}/fixtures/langs-trend" \
    bash "${TOOL}" mine "$repo" --db "$db" --granularity file --trends --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
warnings = json.load(sys.stdin)["warnings"]
assert any(w.startswith("trends:") and "bucket" in w for w in warnings), warnings
'

  rm -rf "$repo"
}
