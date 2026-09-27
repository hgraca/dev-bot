#!/usr/bin/env bats
# =============================================================================
# src/agentic/forensics/tests/forensics_tests.bats
# Tests for the forensics module — lifecycle skeleton (T0.1) and the plugin
# registry contract (T0.2). Later phases append analysis tests here.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="${MODULE_DIR}/tools/forensics.sh"
  LIB="${MODULE_DIR}/lib/forensics-lib.py"
  GM="${MODULE_DIR}/lib/gitmine.py"
  LANGS="${MODULE_DIR}/langs"
  EDGE_LANGS="${TEST_DIR}/fixtures/langs-edge"
  PHP_PLUGIN="${MODULE_DIR}/langs/php/plugin.sh"
  PHP_FIXTURES="${TEST_DIR}/fixtures/php-project"
}

# ── Skeleton (T0.1) ────────────────────────────────────────────────────────────

@test "functions.sh: sources cleanly and exposes shared helpers" {
  run bash -c "source '${MODULE_DIR}/functions.sh' && declare -F _info >/dev/null && declare -F _warn >/dev/null"
  assert_success
}

@test "pre.sh: exits 0" {
  run bash "${MODULE_DIR}/pre.sh"
  assert_success
}

@test "install.sh: is idempotent (second run succeeds)" {
  run bash "${MODULE_DIR}/install.sh"
  assert_success

  run bash "${MODULE_DIR}/install.sh"
  assert_success
}

# ── CLI surface ────────────────────────────────────────────────────────────────

# The tool is a plain CLI, like refactor: the `devbot:forensics` skill documents
# it and an agent runs `devbot tool forensics <command>`. It is NOT an MCP tool.

@test "not an MCP tool: no .mcp.sh wrapper" {
  run bash -c "ls '${MODULE_DIR}'/tools/*.mcp.sh 2>/dev/null"
  assert_failure
}

@test "--version: prints the tool version and exits 0" {
  run bash "${TOOL}" --version
  assert_success
  assert_output --regexp "^forensics [0-9]+\.[0-9]+\.[0-9]+$"
}

@test "--help: prints usage and exits 0" {
  run bash "${TOOL}" --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "mine"
}

@test "no command: prints usage to stderr and exits non-zero" {
  run bash "${TOOL}"
  assert_failure
  assert_output --partial "Usage:"
}

@test "unknown command: fails with an ERROR" {
  run bash "${TOOL}" bogus-command
  assert_failure
  assert_output --partial "ERROR"
}

# ── Plugin registry (T0.2) ─────────────────────────────────────────────────────

@test "langs --format json: emits valid JSON listing the php plugin" {
  run bash "${TOOL}" langs --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert doc["ok"] is True, doc
langs = [p["lang"] for p in doc["plugins"]]
assert "php" in langs, langs
assert doc["errors"] == [], doc["errors"]
'
}

@test "langs: default markdown output names the php plugin" {
  run bash "${TOOL}" langs
  assert_success
  assert_output --partial "php"
}

@test "langs: a malformed plugin is rejected with an ERROR and non-zero exit" {
  run env FORENSICS_LANGS_DIR="${EDGE_LANGS}" bash "${TOOL}" langs --format json
  assert_failure
  assert_output --partial "ERROR"
}

@test "langs: a plugin missing a required meta key is reported as an error" {
  run env FORENSICS_LANGS_DIR="${TEST_DIR}/fixtures/langs-nokey" bash "${TOOL}" langs --format json
  assert_failure
  assert_output --partial "ERROR"
}

# ── Git miner (T0.3) ───────────────────────────────────────────────────────────
#
# The miner is the language-agnostic half of `mine`: it turns a git repo into
# commits + per-commit file changes, boxed to a date range. Fixtures are built in
# a temp dir at test time, so no repo is committed as a nested checkout.

# Build a 3-commit repo with deterministic dates under $1.
_build_repo() {
  local dir="$1"
  git -C "$dir" init -q
  git -C "$dir" config user.name "Alice"
  git -C "$dir" config user.email "alice@example.com"
  git -C "$dir" config commit.gpgsign false

  printf 'line1\nline2\n' >"${dir}/a.php"
  git -C "$dir" add a.php
  GIT_AUTHOR_DATE="2024-01-01T10:00:00+00:00" GIT_COMMITTER_DATE="2024-01-01T10:00:00+00:00" \
    git -C "$dir" commit -q -m "feat(A-1): add a"

  printf 'line1\nline2\nline3\n' >"${dir}/a.php"
  git -C "$dir" add a.php
  GIT_AUTHOR_DATE="2024-02-01T10:00:00+00:00" GIT_COMMITTER_DATE="2024-02-01T10:00:00+00:00" \
    git -C "$dir" commit -q -m "fix(A-1): patch a"

  printf 'b\n' >"${dir}/b.txt"
  git -C "$dir" add b.txt
  GIT_AUTHOR_DATE="2024-03-01T10:00:00+00:00" GIT_COMMITTER_DATE="2024-03-01T10:00:00+00:00" \
    git -C "$dir" commit -q -m "chore: add b"
}

@test "gitmine log: returns every commit with author, date and churn" {
  local repo
  repo="$(mktemp -d)"
  _build_repo "$repo"

  run python3 "${GM}" log --repo "$repo" --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert doc["ok"] is True, doc
assert len(doc["commits"]) == 3, len(doc["commits"])
subjects = [c["message"].splitlines()[0] for c in doc["commits"]]
assert subjects[0].startswith("chore"), subjects
assert doc["commits"][0]["author_name"] == "Alice"
assert any(row["path"] == "a.php" for row in doc["changes"]), doc["changes"]
'

  rm -rf "$repo"
}

@test "gitmine log: --since/--until box the range" {
  local repo
  repo="$(mktemp -d)"
  _build_repo "$repo"

  run python3 "${GM}" log --repo "$repo" --since 2024-02-15 --until 2024-03-15 --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert len(doc["commits"]) == 1, [c["message"] for c in doc["commits"]]
assert doc["commits"][0]["message"].startswith("chore")
'

  rm -rf "$repo"
}

@test "gitmine log: a non-repo path is an ERROR" {
  local dir
  dir="$(mktemp -d)"
  run python3 "${GM}" log --repo "$dir" --format json
  assert_failure
  assert_output --partial "ERROR"
  rm -rf "$dir"
}

@test "gitmine blame: attributes lines to an author" {
  local repo
  repo="$(mktemp -d)"
  _build_repo "$repo"

  run python3 "${GM}" blame --repo "$repo" --file a.php --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert doc["ok"] is True, doc
assert len(doc["lines"]) >= 1
assert doc["lines"][0]["author_name"] == "Alice"
'

  rm -rf "$repo"
}

# ── Store + mine wiring (T0.4 / T0.6) ──────────────────────────────────────────

@test "mine: writes commits, changes and files into a sqlite DB" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/out.sqlite"
  _build_repo "$repo"

  run bash "${TOOL}" mine "$repo" --db "$db" --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert doc["ok"] is True, doc
assert doc["counts"]["commits"] == 3, doc["counts"]
assert doc["counts"]["files"] == 2, doc["counts"]
assert doc["counts"]["changes"] >= 2, doc["counts"]
'

  run python3 -c '
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.row_factory = sqlite3.Row
row = conn.execute("SELECT * FROM files WHERE path=?", ("a.php",)).fetchone()
assert row is not None, "a.php missing from files"
assert row["commits"] == 2, dict(row)
assert row["authors_count"] == 1, dict(row)
assert row["type"] == "php", dict(row)
' "$db"
  assert_success

  rm -rf "$repo"
}

@test "mine: default DB lands in <repo>/.forensics with a self-ignore" {
  local repo
  repo="$(mktemp -d)"
  _build_repo "$repo"

  run bash "${TOOL}" mine "$repo" --format json
  assert_success

  run bash -c "ls '${repo}/.forensics/'*.sqlite"
  assert_success
  run bash -c "cat '${repo}/.forensics/.gitignore'"
  assert_output '*'

  rm -rf "$repo"
}

@test "mine: re-mining the same DB yields identical row counts" {
  local repo db first second
  repo="$(mktemp -d)"
  db="$(mktemp -d)/out.sqlite"
  _build_repo "$repo"

  first="$(bash "${TOOL}" mine "$repo" --db "$db" --format json)"
  second="$(bash "${TOOL}" mine "$repo" --db "$db" --format json)"
  run python3 -c '
import json, sys
a = json.loads(sys.argv[1]); b = json.loads(sys.argv[2])
assert a["counts"] == b["counts"], (a["counts"], b["counts"])
' "$first" "$second"
  assert_success

  rm -rf "$repo"
}

@test "mine: a non-repo path is an ERROR" {
  local dir
  dir="$(mktemp -d)"
  run bash "${TOOL}" mine "$dir" --format json
  assert_failure
  assert_output --partial "ERROR"
  rm -rf "$dir"
}

# ── PHP plugin: units (T0.5) ───────────────────────────────────────────────────

# True when the PHP plugin can run for real (docker + a resolvable engine).
_php_e2e_ready() {
  command -v docker >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1 || return 1
  bash "${PHP_PLUGIN}" doctor --project "${PHP_FIXTURES}" >/dev/null 2>&1
}

@test "php plugin units: no engine is an ERROR" {
  local project storage req
  project="$(mktemp -d)"
  storage="$(mktemp -d)"
  req="$(mktemp)"
  printf '{"project":"%s","files":[]}' "${project}" >"${req}"

  run env FORENSICS_STORAGE_DIR="${storage}" bash "${PHP_PLUGIN}" units <"${req}"
  assert_failure
  assert_output --partial "ERROR"

  rm -rf "$project" "$storage" "$req"
}

@test "php plugin doctor: resolves an engine" {
  _php_e2e_ready || skip "php engine + docker not available"

  run bash "${PHP_PLUGIN}" doctor --project "${PHP_FIXTURES}"
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert doc["ok"] is True, doc
assert doc["engine"]["version"] != "unknown", doc
'
}

@test "php plugin units: emits class + method units with complexity" {
  _php_e2e_ready || skip "php engine + docker not available"

  local req
  req="$(mktemp)"
  printf '{"project":"%s","files":["src/Calculator.php"]}' "${PHP_FIXTURES}" >"${req}"

  run bash "${PHP_PLUGIN}" units <"${req}"
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert doc["ok"] is True, doc
units = {(u["kind"], u["name"]): u for u in doc["units"]}
assert ("class", "Calculator") in units, list(units)
assert units[("class", "Calculator")]["complexity"] == 4, units
assert ("method", "Calculator::add") in units, list(units)
assert units[("method", "Calculator::add")]["complexity"] == 1, units
assert ("method", "Calculator::classify") in units, list(units)
assert units[("method", "Calculator::classify")]["complexity"] == 3, units
'

  rm -f "$req"
}

@test "php plugin units: covers traits and enums" {
  _php_e2e_ready || skip "php engine + docker not available"

  local req
  req="$(mktemp)"
  printf '{"project":"%s","files":["src/Shape.php"]}' "${PHP_FIXTURES}" >"${req}"

  run bash "${PHP_PLUGIN}" units <"${req}"
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
units = {(u["kind"], u["name"]) for u in doc["units"]}
assert ("trait", "Greets") in units, units
assert ("method", "Greets::greet") in units, units
assert ("enum", "Level") in units, units
assert ("method", "Level::label") in units, units
'

  rm -f "$req"
}

# ── Mine unit extraction (T0.6 complete) ───────────────────────────────────────

@test "mine: --granularity file skips unit extraction" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/out.sqlite"
  _build_repo "$repo"

  run bash "${TOOL}" mine "$repo" --db "$db" --granularity file --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert doc["counts"]["units"] == 0, doc["counts"]
'

  rm -rf "$repo"
}

@test "mine: extracts units for php files when an engine is available" {
  _php_e2e_ready || skip "php engine + docker not available"

  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/out.sqlite"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  mkdir -p "$repo/src"
  cp "${PHP_FIXTURES}/src/Calculator.php" "$repo/src/Calculator.php"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2024-01-01T10:00:00+00:00" GIT_COMMITTER_DATE="2024-01-01T10:00:00+00:00" \
    git -C "$repo" commit -q -m "feat: add calculator"

  run bash "${TOOL}" mine "$repo" --db "$db" --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert doc["counts"]["units"] >= 3, doc["counts"]
'

  run python3 -c '
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.row_factory = sqlite3.Row
row = conn.execute("SELECT * FROM units WHERE kind=? ORDER BY complexity DESC", ("method",)).fetchone()
assert row is not None, "no method units stored"
assert row["complexity"] >= 1, dict(row)
' "$db"
  assert_success

  rm -rf "$repo"
}

# ── Provision CLI ──────────────────────────────────────────────────────────────

@test "provision: missing --lang is an ERROR" {
  run bash "${TOOL}" provision
  assert_failure
  assert_output --partial "ERROR"
}

@test "provision: unknown language is an ERROR" {
  run bash "${TOOL}" provision --lang nosuchlang
  assert_failure
  assert_output --partial "ERROR"
}

# ── Review fixes ───────────────────────────────────────────────────────────────

@test "mine: --db outside .forensics never writes a repo-root .gitignore" {
  local repo
  repo="$(mktemp -d)"
  _build_repo "$repo"

  run bash "${TOOL}" mine "$repo" --db "$repo/out.sqlite" --granularity file --format json
  assert_success
  refute [ -f "$repo/.gitignore" ]

  rm -rf "$repo"
}

@test "mine: an empty repository is an ERROR, not a traceback" {
  local repo
  repo="$(mktemp -d)"
  git -C "$repo" init -q

  run bash "${TOOL}" mine "$repo" --db "$(mktemp -d)/out.sqlite" --format json
  assert_failure
  assert_output --partial "ERROR"
  refute_output --partial "Traceback"

  rm -rf "$repo"
}

@test "gitmine log: keeps non-ASCII paths unquoted" {
  local repo
  repo="$(mktemp -d)"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  printf 'x\n' >"$repo/café.php"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2024-01-01T10:00:00+00:00" GIT_COMMITTER_DATE="2024-01-01T10:00:00+00:00" \
    git -C "$repo" commit -q -m "feat: café"

  run python3 "${GM}" log --repo "$repo" --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
paths = [c["path"] for c in doc["changes"]]
assert "café.php" in paths, paths
'

  rm -rf "$repo"
}

@test "gitmine log: records a rename with old and new paths" {
  local repo
  repo="$(mktemp -d)"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  printf 'x\n' >"$repo/old.php"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2024-01-01T10:00:00+00:00" GIT_COMMITTER_DATE="2024-01-01T10:00:00+00:00" \
    git -C "$repo" commit -q -m "feat: old"
  git -C "$repo" mv old.php new.php
  GIT_AUTHOR_DATE="2024-02-01T10:00:00+00:00" GIT_COMMITTER_DATE="2024-02-01T10:00:00+00:00" \
    git -C "$repo" commit -q -m "refactor: rename old to new"

  run python3 "${GM}" log --repo "$repo" --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
renames = [c for c in doc["changes"] if c["is_rename"]]
assert any(r["path"] == "new.php" and r["old_path"] == "old.php" for r in renames), renames
'

  rm -rf "$repo"
}

@test "mine: a subdirectory argument mines at the repo root" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/out.sqlite"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  mkdir -p "$repo/src"
  printf '<?php\nclass A {}\n' >"$repo/src/A.php"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2024-01-01T10:00:00+00:00" GIT_COMMITTER_DATE="2024-01-01T10:00:00+00:00" \
    git -C "$repo" commit -q -m "feat: a"

  run bash "${TOOL}" mine "$repo/src" --db "$db" --granularity file --format json
  assert_success
  echo "${output}" | python3 -c '
import json, os, sys
doc = json.load(sys.stdin)
assert os.path.realpath(doc["repo"]) == os.path.realpath(sys.argv[1]), doc["repo"]
' "$repo"

  run python3 -c '
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
paths = {row[0] for row in conn.execute("SELECT path FROM files")}
assert "src/A.php" in paths, paths
' "$db"
  assert_success

  rm -rf "$repo"
}

@test "mine: a subdirectory argument writes .forensics at the repo root" {
  local repo
  repo="$(mktemp -d)"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  mkdir -p "$repo/src"
  printf '<?php\nclass A {}\n' >"$repo/src/A.php"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2024-01-01T10:00:00+00:00" GIT_COMMITTER_DATE="2024-01-01T10:00:00+00:00" \
    git -C "$repo" commit -q -m "feat: a"

  run bash "${TOOL}" mine "$repo/src" --granularity file --format json
  assert_success
  [ -d "$repo/.forensics" ]
  refute [ -d "$repo/src/.forensics" ]

  rm -rf "$repo"
}

@test "mine: an unknown --lang is an ERROR" {
  local repo
  repo="$(mktemp -d)"
  _build_repo "$repo"

  run bash "${TOOL}" mine "$repo" --db "$(mktemp -d)/o.sqlite" --lang nosuchlang --granularity file --format json
  assert_failure
  assert_output --partial "ERROR"

  rm -rf "$repo"
}

@test "mine: --lang php is accepted" {
  local repo
  repo="$(mktemp -d)"
  _build_repo "$repo"

  run bash "${TOOL}" mine "$repo" --db "$(mktemp -d)/o.sqlite" --lang php --granularity file --format json
  assert_success

  rm -rf "$repo"
}

@test "mine: a failing unit plugin does not discard another plugin's units" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/o.sqlite"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  printf 'x\n' >"$repo/a.zz"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2024-01-01T10:00:00+00:00" GIT_COMMITTER_DATE="2024-01-01T10:00:00+00:00" \
    git -C "$repo" commit -q -m "feat: zz"

  run env FORENSICS_LANGS_DIR="${TEST_DIR}/fixtures/langs-multi" bash "${TOOL}" mine "$repo" --db "$db" --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert doc["counts"]["units"] >= 1, doc["counts"]
assert any("bad" in w for w in doc["warnings"]), doc["warnings"]
'

  rm -rf "$repo"
}

@test "php plugin doctor: JSON stays valid with a quote in the project path" {
  local base dir
  base="$(mktemp -d)"
  dir="${base}/we\"ird"
  mkdir -p "$dir"

  run env FORENSICS_STORAGE_DIR="$(mktemp -d)" bash "${PHP_PLUGIN}" doctor --project "$dir"
  echo "${output}" | python3 -c 'import json, sys; json.load(sys.stdin)'

  rm -rf "$base"
}

@test "php plugin doctor: prefers the php app service, not the db service" {
  local project
  project="$(mktemp -d)"
  cp "${TEST_DIR}/fixtures/php-project-with-compose/compose.yml" "${project}/compose.yml"
  # A project-local engine so image resolution reaches the compose path (a
  # scratch engine would win with its own PHP image first).
  mkdir -p "${project}/vendor/pdepend/pdepend"
  printf '<?php\n' >"${project}/vendor/autoload.php"

  run bash "${PHP_PLUGIN}" doctor --project "$project"
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert doc["image"] == "myorg/app:1.0", doc
assert doc["engine"]["via"] == "project", doc
'

  rm -rf "$project"
}

# ── Phase 1: hotspots ──────────────────────────────────────────────────────────

@test "analyse hotspots: ranks complexity x change rate" {
  run python3 -c '
import sqlite3, sys
sys.path.insert(0, sys.argv[1] + "/lib")
import analyse, store

conn = sqlite3.connect(":memory:")
conn.row_factory = sqlite3.Row
store.init(conn)

def commit(h, day):
    store.write_commits(conn, [{"hash": h, "author_name": "A", "author_email": "a",
                                "date": "2024-01-0%sT00:00:00+00:00" % day, "message": "m",
                                "files_changed": 1, "lines_added": 1, "lines_deleted": 0}])

def change(h, path):
    store.write_changes(conn, [{"commit_hash": h, "path": path, "added": 1, "deleted": 0,
                                "is_rename": False, "old_path": ""}])

commit("h1", 1); change("h1", "hot.php"); change("h1", "cold.php")
for i, day in enumerate([2, 3, 4, 5], start=2):
    commit("h%d" % i, day); change("h%d" % i, "hot.php")
store.derive_files(conn)
store.write_units(conn, [
    {"path": "hot.php", "name": "Hot", "kind": "class", "start_line": 1, "end_line": 1, "complexity": 10, "loc": 1, "parent": ""},
    {"path": "cold.php", "name": "Cold", "kind": "class", "start_line": 1, "end_line": 1, "complexity": 5, "loc": 1, "parent": ""},
])
conn.commit()

rows = analyse.hotspots(conn)
assert rows[0]["path"] == "hot.php", rows
assert rows[0]["commits"] == 5 and rows[0]["complexity"] == 10, rows
assert rows[1]["path"] == "cold.php", rows
' "${MODULE_DIR}"
}

@test "analyse hotspots: runs over a mined database" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/out.sqlite"
  _build_repo "$repo"

  run bash "${TOOL}" mine "$repo" --db "$db" --granularity file --format json
  assert_success

  run bash "${TOOL}" analyse "$db" --view hotspots --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert doc["ok"] is True, doc
assert doc["view"] == "hotspots", doc
assert isinstance(doc["hotspots"], list), doc
'

  rm -rf "$repo"
}

@test "analyse: a missing database is an ERROR" {
  run bash "${TOOL}" analyse /nonexistent/forensics.sqlite --format json
  assert_failure
  assert_output --partial "ERROR"
}

@test "analyse: an unimplemented view is an ERROR" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/out.sqlite"
  _build_repo "$repo"
  bash "${TOOL}" mine "$repo" --db "$db" --granularity file >/dev/null

  run bash "${TOOL}" analyse "$db" --view no-such-view --format json
  assert_failure
  assert_output --partial "ERROR"

  rm -rf "$repo"
}

@test "analyse: --format csv exports the view rows" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/out.sqlite"
  _build_repo "$repo"
  bash "${TOOL}" mine "$repo" --db "$db" --granularity file >/dev/null

  run bash "${TOOL}" analyse "$db" --view change-rate --format csv
  assert_success
  assert_output --partial "path,type,commits"
  refute_output --partial "Traceback"

  rm -rf "$repo"
}

@test "analyse: markdown output works for any view" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/out.sqlite"
  _build_repo "$repo"
  bash "${TOOL}" mine "$repo" --db "$db" --granularity file >/dev/null

  run bash "${TOOL}" analyse "$db" --view change-rate --format md
  assert_success
  assert_output --partial "| path |"
  refute_output --partial "Traceback"

  rm -rf "$repo"
}

@test "analyse change-rate: ranks by commits and computes commits per active day" {
  run python3 -c '
import sqlite3, sys
sys.path.insert(0, sys.argv[1] + "/lib")
import analyse, store

conn = sqlite3.connect(":memory:")
conn.row_factory = sqlite3.Row
store.init(conn)

def commit(h, day, files):
    store.write_commits(conn, [{"hash": h, "author_name": "A", "author_email": "a",
        "date": "2024-01-%02dT00:00:00+00:00" % day, "message": "m",
        "files_changed": len(files), "lines_added": 1, "lines_deleted": 0}])
    store.write_changes(conn, [{"commit_hash": h, "path": p, "added": 1, "deleted": 0,
        "is_rename": False, "old_path": ""} for p in files])

commit("h1", 1, ["a.php"]); commit("h2", 1, ["a.php"]); commit("h3", 2, ["b.php"])
store.derive_files(conn)

rows = analyse.change_rate(conn)
top = rows[0]
assert top["path"] == "a.php" and top["commits"] == 2 and top["active_days"] == 1 and top["rate"] == 2.0, top
' "${MODULE_DIR}"
}

@test "analyse coupling: finds co-changing pairs and drops bulk commits" {
  run python3 -c '
import sqlite3, sys
sys.path.insert(0, sys.argv[1] + "/lib")
import analyse, store

conn = sqlite3.connect(":memory:")
conn.row_factory = sqlite3.Row
store.init(conn)

def commit(h, day, files):
    store.write_commits(conn, [{"hash": h, "author_name": "A", "author_email": "a",
        "date": "2024-02-%02dT00:00:00+00:00" % day, "message": "m",
        "files_changed": len(files), "lines_added": 1, "lines_deleted": 0}])
    store.write_changes(conn, [{"commit_hash": h, "path": p, "added": 1, "deleted": 0,
        "is_rename": False, "old_path": ""} for p in files])

commit("h1", 1, ["a.php", "b.php"])
commit("h2", 2, ["a.php", "b.php"])
commit("h3", 3, ["f%02d.php" % i for i in range(40)])  # bulk: must be ignored
store.derive_files(conn)

rows = {frozenset((r["path_a"], r["path_b"])): r for r in analyse.coupling(conn)}
pair = rows[frozenset(("a.php", "b.php"))]
assert pair["shared_commits"] == 2, pair
assert pair["coupling_pct"] == 100.0, pair
assert len(rows) == 1, list(rows)
' "${MODULE_DIR}"
}

@test "analyse ownership + concentration: flag single-owner knowledge risk" {
  run python3 -c '
import sqlite3, sys
sys.path.insert(0, sys.argv[1] + "/lib")
import analyse, store

conn = sqlite3.connect(":memory:")
conn.row_factory = sqlite3.Row
store.init(conn)

def commit(h, author, files):
    store.write_commits(conn, [{"hash": h, "author_name": author, "author_email": author + "@x",
        "date": "2024-03-01T00:00:00+00:00", "message": "m", "files_changed": len(files),
        "lines_added": 1, "lines_deleted": 0}])
    store.write_changes(conn, [{"commit_hash": h, "path": p, "added": 1, "deleted": 0,
        "is_rename": False, "old_path": ""} for p in files])

commit("h1", "alice", ["shared.php", "solo.php"])
commit("h2", "bob", ["shared.php"])
commit("h3", "alice", ["solo.php"])
commit("h4", "alice", ["solo.php"])
store.derive_files(conn)

own = {r["path"]: r for r in analyse.ownership(conn)}
assert own["solo.php"]["authors"] == 1, own["solo.php"]
assert own["shared.php"]["authors"] == 2, own["shared.php"]

conc = {r["path"] for r in analyse.concentration(conn)}
assert "solo.php" in conc and "shared.php" not in conc, conc

assert analyse.bus_factor(conn)["bus_factor"] == 1, analyse.bus_factor(conn)
' "${MODULE_DIR}"
}

@test "commitparse: parses conventional type, scope, ticket and breaking" {
  run python3 -c '
import sys
sys.path.insert(0, sys.argv[1] + "/lib")
import commitparse
doc = commitparse.parse_message("fix(PROJ-42)!: correct totals\n\nBREAKING CHANGE: api")
assert doc["type"] == "fix", doc
assert doc["scope"] == "PROJ-42", doc
assert doc["ticket"] == "PROJ-42", doc
assert doc["breaking"] == 1, doc
assert commitparse.parse_message("random message")["conventional"] is False
' "${MODULE_DIR}"
}

@test "analyse commit-types/tickets: reports the conventional mix after mine" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/o.sqlite"
  _build_repo "$repo"

  run bash "${TOOL}" mine "$repo" --db "$db" --granularity file --format json
  assert_success

  run bash "${TOOL}" analyse "$db" --view commit-types --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
types = {r["type"] for r in doc["commit-types"]}
assert {"feat", "fix", "chore"} <= types, types
'

  run bash "${TOOL}" analyse "$db" --view tickets --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert any(r["ticket"] == "A-1" for r in doc["tickets"]), doc["tickets"]
'

  rm -rf "$repo"
}

# ── Defect origin (SZZ) ────────────────────────────────────────────────────────

@test "szz: links a fix to the commit that introduced the faulty line" {
  local repo
  repo="$(mktemp -d)"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  printf 'one\n' >"$repo/f.php"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2024-01-01T00:00:00+00:00" GIT_COMMITTER_DATE="2024-01-01T00:00:00+00:00" \
    git -C "$repo" commit -q -m "feat: v1"
  printf 'two\n' >"$repo/f.php"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2024-01-02T12:00:00+00:00" GIT_COMMITTER_DATE="2024-01-02T12:00:00+00:00" \
    git -C "$repo" commit -q -m "fix: v2"

  run python3 -c '
import sys
sys.path.insert(0, sys.argv[1] + "/lib")
import commitparse, gitmine, szz
repo = sys.argv[2]
commits = commitparse.enrich(gitmine.mine_log(repo)["commits"])
links = szz.link_defects(repo, commits)
assert len(links) == 1, links
link = links[0]
fix = next(c for c in commits if c["hash"] == link["fix_hash"])
inducing = next(c for c in commits if c["hash"] == link["inducing_hash"])
assert fix["type"] == "fix", fix
assert inducing["message"].startswith("feat"), inducing
assert link["delta_seconds"] == 36 * 3600, link
' "${MODULE_DIR}" "$repo"

  rm -rf "$repo"
}

@test "analyse time-to-fix: reports the inducing-to-fix distribution" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/o.sqlite"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  printf 'one\n' >"$repo/f.php"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2024-01-01T00:00:00+00:00" GIT_COMMITTER_DATE="2024-01-01T00:00:00+00:00" \
    git -C "$repo" commit -q -m "feat: v1"
  printf 'two\n' >"$repo/f.php"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2024-01-02T12:00:00+00:00" GIT_COMMITTER_DATE="2024-01-02T12:00:00+00:00" \
    git -C "$repo" commit -q -m "fix: v2"

  run bash "${TOOL}" mine "$repo" --db "$db" --granularity file --format json
  assert_success

  run bash "${TOOL}" analyse "$db" --view time-to-fix --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
row = doc["time-to-fix"][0]
assert row["count"] >= 1, row
assert row["fastest_hours"] == 36.0, row
'

  run bash "${TOOL}" analyse "$db" --view fixers --format json
  assert_success

  rm -rf "$repo"
}

# ── Report (Phase 1) ───────────────────────────────────────────────────────────

@test "report: renders markdown with hotspots and a methodology footer" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/o.sqlite"
  _build_repo "$repo"
  bash "${TOOL}" mine "$repo" --db "$db" --granularity file >/dev/null

  run bash "${TOOL}" report "$db" --format md
  assert_success
  assert_output --partial "# Code forensics report"
  assert_output --partial "## Hotspots"
  assert_output --partial "## Ownership"
  assert_output --partial "## Methodology"

  rm -rf "$repo"
}

@test "report: --format json returns the assembled views" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/o.sqlite"
  _build_repo "$repo"
  bash "${TOOL}" mine "$repo" --db "$db" --granularity file >/dev/null

  run bash "${TOOL}" report "$db" --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
for key in ("meta", "hotspots", "coupling", "authors", "time-to-fix", "bus_factor"):
    assert key in doc, key
'

  rm -rf "$repo"
}

@test "report: --out writes report.md" {
  local repo db out
  repo="$(mktemp -d)"
  db="$(mktemp -d)/o.sqlite"
  out="$(mktemp -d)"
  _build_repo "$repo"
  bash "${TOOL}" mine "$repo" --db "$db" --granularity file >/dev/null

  run bash "${TOOL}" report "$db" --out "$out" --format md
  assert_success
  [ -f "$out/report.md" ]

  rm -rf "$repo"
}

@test "analyse process: reports batch size and conventional compliance" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/o.sqlite"
  _build_repo "$repo"
  bash "${TOOL}" mine "$repo" --db "$db" --granularity file >/dev/null

  run bash "${TOOL}" analyse "$db" --view process --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
row = json.load(sys.stdin)["process"][0]
assert row["commits"] == 3, row
assert row["conventional_pct"] == 100.0, row
assert row["avg_files_per_commit"] == 1.0, row
'

  rm -rf "$repo"
}

@test "ownership aggregate: maps blame lines onto unit spans" {
  run python3 -c '
import sys
sys.path.insert(0, sys.argv[1] + "/lib")
import ownership
lines = [
    {"line": 1, "author_email": "a@x", "hash": "h1", "date": "2024-01-01T00:00:00+00:00"},
    {"line": 2, "author_email": "a@x", "hash": "h1", "date": "2024-01-01T00:00:00+00:00"},
    {"line": 3, "author_email": "b@x", "hash": "h2", "date": "2024-02-01T00:00:00+00:00"},
]
units = [{"path": "f.php", "name": "f", "kind": "function", "start_line": 1, "end_line": 3}]
own, churn = ownership.aggregate_units(lines, units)
authors = {r["author"]: r["lines_owned"] for r in own}
assert authors == {"a@x": 2, "b@x": 1}, authors
assert churn[0]["commits"] == 2 and churn[0]["active_days"] == 2, churn
assert own[0]["unit_key"] == ownership.unit_key("f.php", "function", "f"), own
' "${MODULE_DIR}"
}

@test "mine unit-ownership: attributes a unit to its author" {
  _php_e2e_ready || skip "php engine + docker not available"

  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/o.sqlite"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  mkdir -p "$repo/src"
  cp "${PHP_FIXTURES}/src/Calculator.php" "$repo/src/Calculator.php"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2024-01-01T10:00:00+00:00" GIT_COMMITTER_DATE="2024-01-01T10:00:00+00:00" \
    git -C "$repo" commit -q -m "feat: add calculator"

  run bash "${TOOL}" mine "$repo" --db "$db" --format json
  assert_success

  run bash "${TOOL}" analyse "$db" --view unit-ownership --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
names = {r["name"]: r for r in doc["unit-ownership"]}
assert "Calculator::classify" in names, list(names)
assert names["Calculator::classify"]["authors"] == 1, names["Calculator::classify"]
'

  rm -rf "$repo"
}

@test "analyse process: reports release cadence from tags" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/o.sqlite"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  printf 'a\n' >"$repo/a.php"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2024-01-01T00:00:00+00:00" GIT_COMMITTER_DATE="2024-01-01T00:00:00+00:00" \
    git -C "$repo" commit -q -m "feat: a"
  git -C "$repo" tag v1
  printf 'b\n' >"$repo/b.php"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2024-01-11T00:00:00+00:00" GIT_COMMITTER_DATE="2024-01-11T00:00:00+00:00" \
    git -C "$repo" commit -q -m "feat: b"
  git -C "$repo" tag v2

  run bash "${TOOL}" mine "$repo" --db "$db" --granularity file --format json
  assert_success

  run bash "${TOOL}" analyse "$db" --view process --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
row = json.load(sys.stdin)["process"][0]
assert row["tags"] == 2, row
assert row["avg_days_between_releases"] == 10.0, row
'

  run bash "${TOOL}" analyse "$db" --view releases --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
tags = [r["tag"] for r in json.load(sys.stdin)["releases"]]
assert tags == ["v1", "v2"], tags
'

  rm -rf "$repo"
}

# ── Phase 1 review fixes ───────────────────────────────────────────────────────

@test "analyse percentile ranks: equal values share a rank" {
  run python3 -c '
import sys
sys.path.insert(0, sys.argv[1] + "/lib")
import analyse
assert analyse._percentile_ranks([5, 5, 5]) == [0.0, 0.0, 0.0], analyse._percentile_ranks([5, 5, 5])
assert analyse._percentile_ranks([1, 2, 2, 3]) == [0.0, 1 / 3, 1 / 3, 1.0], analyse._percentile_ranks([1, 2, 2, 3])
' "${MODULE_DIR}"
}

@test "analyse/report: an incompatible database is an ERROR" {
  local db
  db="$(mktemp -d)/foreign.sqlite"
  python3 -c '
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("CREATE TABLE meta(key TEXT, value TEXT)")
conn.commit()
' "$db"

  run bash "${TOOL}" analyse "$db" --format json
  assert_failure
  assert_output --partial "ERROR"

  run bash "${TOOL}" report "$db" --format md
  assert_failure
  assert_output --partial "ERROR"
}

@test "commitparse: rejects non-conventional types and subject acronyms" {
  run python3 -c '
import sys
sys.path.insert(0, sys.argv[1] + "/lib")
import commitparse
for message in ("http: fetch", "WIP: stuff", "Fix: uppercase"):
    assert commitparse.parse_message(message)["conventional"] is False, message
assert commitparse.parse_message("fix(UTF): x")["ticket"] == ""
assert commitparse.parse_message("fix: bump UTF-8")["ticket"] == ""
' "${MODULE_DIR}"
}

@test "szz: links a fix on a non-ASCII path" {
  local repo
  repo="$(mktemp -d)"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  printf 'one\n' >"$repo/café.php"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2024-01-01T00:00:00+00:00" GIT_COMMITTER_DATE="2024-01-01T00:00:00+00:00" \
    git -C "$repo" commit -q -m "feat: v1"
  printf 'two\n' >"$repo/café.php"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2024-01-02T12:00:00+00:00" GIT_COMMITTER_DATE="2024-01-02T12:00:00+00:00" \
    git -C "$repo" commit -q -m "fix: v2"

  run python3 -c '
import sys
sys.path.insert(0, sys.argv[1] + "/lib")
import commitparse, gitmine, szz
repo = sys.argv[2]
commits = commitparse.enrich(gitmine.mine_log(repo)["commits"])
links = szz.link_defects(repo, commits)
assert len(links) == 1, links
assert links[0]["inducing_hash"], links
' "${MODULE_DIR}" "$repo"

  rm -rf "$repo"
}

# ── Phase 2: composite priority ────────────────────────────────────────────────

@test "analyse priority: ranks recurring pain above a quiet file" {
  run python3 -c '
import sqlite3, sys
sys.path.insert(0, sys.argv[1] + "/lib")
import analyse, store

conn = sqlite3.connect(":memory:")
conn.row_factory = sqlite3.Row
store.init(conn)

def commit(h, day, author, ctype, files):
    store.write_commits(conn, [{"hash": h, "author_name": author, "author_email": author + "@x",
        "date": "2024-04-%02dT00:00:00+00:00" % day, "message": "m", "type": ctype, "scope": "",
        "ticket": "", "breaking": 0, "files_changed": len(files), "lines_added": 1, "lines_deleted": 0}])
    store.write_changes(conn, [{"commit_hash": h, "path": p, "added": 1, "deleted": 0,
        "is_rename": False, "old_path": ""} for p in files])

for i in range(1, 6):
    commit("h%d" % i, i, "alice", "fix" if i <= 2 else "feat", ["hot.php"])
commit("c1", 6, "alice", "feat", ["cold.php"])
commit("c2", 7, "bob", "feat", ["cold.php"])

store.derive_files(conn)
store.write_units(conn, [
    {"path": "hot.php", "name": "Hot", "kind": "method", "start_line": 1, "end_line": 1, "complexity": 10, "loc": 1, "parent": ""},
    {"path": "cold.php", "name": "Cold", "kind": "method", "start_line": 1, "end_line": 1, "complexity": 1, "loc": 1, "parent": ""},
])
conn.commit()

rows = analyse.priority(conn)
assert rows[0]["path"] == "hot.php", rows
for key in ("priority", "change_rank", "complexity_rank", "coupling_rank", "defect_rank", "ownership_risk"):
    assert key in rows[0], key
assert rows[0]["ownership_risk"] == 1.0, rows[0]
' "${MODULE_DIR}"
}

@test "mine trends: tracks a file's complexity growth over time" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/o.sqlite"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  printf 'if a\n' >"$repo/code.zz"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2024-01-01T00:00:00+00:00" GIT_COMMITTER_DATE="2024-01-01T00:00:00+00:00" \
    git -C "$repo" commit -q -m "feat: one branch"
  printf 'if a\nif b\n' >"$repo/code.zz"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2024-02-01T00:00:00+00:00" GIT_COMMITTER_DATE="2024-02-01T00:00:00+00:00" \
    git -C "$repo" commit -q -m "feat: another branch"

  run env FORENSICS_LANGS_DIR="${TEST_DIR}/fixtures/langs-trend" bash "${TOOL}" mine "$repo" --db "$db" --trends --format json
  assert_success

  run bash "${TOOL}" analyse "$db" --view trends --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
rows = {row["path"]: row for row in json.load(sys.stdin)["trends"]}
assert rows["code.zz"]["snapshots"] == 2, rows
assert rows["code.zz"]["first_complexity"] == 1, rows
assert rows["code.zz"]["last_complexity"] == 2, rows
assert rows["code.zz"]["delta"] == 1, rows
'

  rm -rf "$repo"
}

# ── Phase 2: external defects + risk ───────────────────────────────────────────

@test "mine defects CSV: joins external defect counts" {
  local repo db csv
  repo="$(mktemp -d)"
  db="$(mktemp -d)/o.sqlite"
  csv="$(mktemp)"
  _build_repo "$repo"
  printf 'path,count\na.php,3\nb.txt,1\n' >"$csv"

  run bash "${TOOL}" mine "$repo" --db "$db" --granularity file --defects "$csv" --format json
  assert_success

  run bash "${TOOL}" analyse "$db" --view defect-density --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
rows = {row["path"]: row for row in json.load(sys.stdin)["defect-density"]}
assert rows["a.php"]["defects"] == 3, rows
'

  rm -rf "$repo"
}

@test "analyse risk: multiplies priority by external defects" {
  run python3 -c '
import sqlite3, sys
sys.path.insert(0, sys.argv[1] + "/lib")
import analyse, store

conn = sqlite3.connect(":memory:")
conn.row_factory = sqlite3.Row
store.init(conn)

def commit(h, day, files):
    store.write_commits(conn, [{"hash": h, "author_name": "A", "author_email": "a@x",
        "date": "2024-05-%02dT00:00:00+00:00" % day, "message": "m", "type": "feat", "scope": "",
        "ticket": "", "breaking": 0, "files_changed": len(files), "lines_added": 1, "lines_deleted": 0}])
    store.write_changes(conn, [{"commit_hash": h, "path": p, "added": 1, "deleted": 0,
        "is_rename": False, "old_path": ""} for p in files])

for i in range(1, 4):
    commit("h%d" % i, i, ["hot.php"])
store.derive_files(conn)
store.write_units(conn, [
    {"path": "hot.php", "name": "H", "kind": "method", "start_line": 1, "end_line": 1, "complexity": 5, "loc": 1, "parent": ""},
])
store.write_defects(conn, [{"path": "hot.php", "count": 2, "source": "csv"}])
conn.commit()

rows = analyse.risk(conn)
assert rows and rows[0]["path"] == "hot.php", rows
assert rows[0]["defects"] == 2, rows
assert rows[0]["risk"] == round(rows[0]["priority"] * 3, 4), rows
' "${MODULE_DIR}"
}

# ── Phase 2: architecture vs organization ──────────────────────────────────────

@test "analyse architecture: flags cross-module coupling" {
  local repo db
  repo="$(mktemp -d)"
  db="$(mktemp -d)/o.sqlite"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Alice"
  git -C "$repo" config user.email "alice@example.com"
  git -C "$repo" config commit.gpgsign false
  mkdir -p "$repo/src/Api" "$repo/src/Domain"
  printf '<?php\n' >"$repo/src/Api/a.php"
  printf '<?php\n' >"$repo/src/Domain/b.php"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2024-01-01T00:00:00+00:00" GIT_COMMITTER_DATE="2024-01-01T00:00:00+00:00" \
    git -C "$repo" commit -q -m "feat: add"
  printf '<?php\n// x\n' >>"$repo/src/Api/a.php"
  printf '<?php\n// y\n' >>"$repo/src/Domain/b.php"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2024-02-01T00:00:00+00:00" GIT_COMMITTER_DATE="2024-02-01T00:00:00+00:00" \
    git -C "$repo" commit -q -m "feat: change both"

  run bash "${TOOL}" mine "$repo" --db "$db" --granularity file \
    --modules "api=src/Api,domain=src/Domain" --format json
  assert_success

  run bash "${TOOL}" analyse "$db" --view architecture --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
rows = json.load(sys.stdin)["architecture"]
assert any({r["module_a"], r["module_b"]} == {"api", "domain"} and r["shared_commits"] >= 2 for r in rows), rows
'

  run bash "${TOOL}" analyse "$db" --view modules --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
mods = {r["module"] for r in json.load(sys.stdin)["modules"]}
assert {"api", "domain"} <= mods, mods
'

  rm -rf "$repo"
}
