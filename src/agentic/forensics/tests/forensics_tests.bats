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
