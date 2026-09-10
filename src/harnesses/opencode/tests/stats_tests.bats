#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode/tests/stats_tests.bats
# Tests for the opencode `devbot stats` adapter.
#
# The adapter reads the opencode SQLite DB (OPENCODE_DB_PATH override), applies
# the day window and project scope, attributes per-step cost/tokens to the tools
# in that step (even split), classifies MCP tools against the configured server
# names, and prints canonical JSON.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"

  SANDBOX="$(mktemp -d)"
  export OPENCODE_DB_PATH="${SANDBOX}/opencode.db"
  PROJECT_DIR="${SANDBOX}/project"
  OTHER_DIR="${SANDBOX}/other"
  mkdir -p "${PROJECT_DIR}" "${OTHER_DIR}"

  # Project config declares one MCP server named `demo`.
  cat > "${PROJECT_DIR}/opencode.jsonc" <<'JSON'
{ "mcp": { "demo": { "type": "local", "command": ["true"] } } }
JSON

  python3 - "${OPENCODE_DB_PATH}" "${PROJECT_DIR}" "${OTHER_DIR}" <<'PY'
import json, sqlite3, sys, time
db, proj, other = sys.argv[1], sys.argv[2], sys.argv[3]
c = sqlite3.connect(db)
c.executescript(
    """
    CREATE TABLE session(id TEXT PRIMARY KEY, directory TEXT, time_created INTEGER, time_updated INTEGER);
    CREATE TABLE part(id TEXT PRIMARY KEY, message_id TEXT, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);
    """
)
now = int(time.time() * 1000)

def session(sid, directory, ts):
    c.execute("INSERT INTO session VALUES(?,?,?,?)", (sid, directory, ts, ts))

def part(sid, ts, obj):
    c.execute(
        "INSERT INTO part VALUES(?,?,?,?,?,?)",
        (f"{sid}-{ts}-{id(obj)}", "m1", sid, ts, ts, json.dumps(obj)),
    )

def tool(name):
    return {"type": "tool", "tool": name, "state": {"status": "completed"}}

def finish(cost, total):
    return {"type": "step-finish", "cost": cost, "tokens": {"total": total}}

# Recent session in the current project: two steps.
session("ses-proj", proj, now - 1000)
part("ses-proj", now - 900, tool("demo_foo"))
part("ses-proj", now - 800, tool("bash"))
part("ses-proj", now - 700, finish(1.0, 100))   # split 0.5/50 across demo_foo+bash
part("ses-proj", now - 600, tool("read"))
part("ses-proj", now - 500, finish(0.2, 20))    # read gets 0.2/20

# Recent session in another project (must be excluded unless --all).
session("ses-other", other, now - 1000)
part("ses-other", now - 900, tool("demo_bar"))
part("ses-other", now - 800, finish(0.3, 30))

# Old session, outside a 30-day window.
old = now - 40 * 86400 * 1000
session("ses-old", proj, old)
part("ses-old", old, tool("demo_old"))
part("ses-old", old + 10, finish(9.9, 999))

c.commit()
c.close()
PY
}

teardown() {
  rm -rf "${SANDBOX}"
}

run_adapter() {
  ( cd "${PROJECT_DIR}" && bash "${MODULE_DIR}/stats.sh" "$@" )
}

json() {
  # $1 = python expression over the parsed `data`
  python3 -c "
import json, sys
data = json.load(sys.stdin)
print(eval(sys.argv[1]))
" "$1"
}

# ── Contract ──────────────────────────────────────────────────────────────────

@test "adapter emits canonical JSON with harness, scope and cost_kind" {
  run run_adapter --days=30
  [ "${status}" -eq 0 ]
  assert_output --partial '"schema": 1'

  echo "${output}" | json "data['harness']" | grep -Fqx "opencode"
  echo "${output}" | json "data['scope']" | grep -Fqx "current"
  echo "${output}" | json "data['cost_kind']" | grep -Fqx "estimated"
}

@test "adapter counts tools and splits step cost/tokens across the step's tools" {
  run run_adapter --days=30
  [ "${status}" -eq 0 ]

  # demo_foo + bash share step 1 (cost 1.0 / tokens 100) → 0.5 / 50 each
  echo "${output}" | json "[(t['name'], t['count'], round(t['cost'],2), t['tokens']) for t in data['tools'] if t['name']=='demo_foo'][0]" | grep -Fqx "('demo_foo', 1, 0.5, 50)"
  echo "${output}" | json "[(t['name'], t['count'], round(t['cost'],2), t['tokens']) for t in data['tools'] if t['name']=='bash'][0]" | grep -Fqx "('bash', 1, 0.5, 50)"
  echo "${output}" | json "[(t['name'], round(t['cost'],2)) for t in data['tools'] if t['name']=='read'][0]" | grep -Fqx "('read', 0.2)"
}

@test "adapter aggregates MCP tools by configured server" {
  run run_adapter --days=30
  [ "${status}" -eq 0 ]

  echo "${output}" | json "[(s['server'], s['count']) for s in data['mcp_servers']]" | grep -Fqx "[('demo', 1)]"
  echo "${output}" | json "[(t['name'], t['count']) for s in data['mcp_servers'] if s['server']=='demo' for t in s['tools']]" | grep -Fqx "[('foo', 1)]"
}

@test "adapter excludes other projects by default and includes them with --all" {
  run run_adapter --days=30
  refute_output --partial '"demo_bar"'

  run run_adapter --days=30 --all
  [ "${status}" -eq 0 ]
  assert_output --partial '"demo_bar"'
  echo "${output}" | json "[(s['server'], s['count']) for s in data['mcp_servers']]" | grep -Fqx "[('demo', 2)]"
}

@test "adapter excludes tool calls older than the day window" {
  run run_adapter --days=30
  refute_output --partial '"demo_old"'

  run run_adapter --days=60
  assert_output --partial '"demo_old"'
}

@test "adapter fails clearly when the database is missing" {
  export OPENCODE_DB_PATH="${SANDBOX}/does-not-exist.db"
  run run_adapter --days=30
  [ "${status}" -ne 0 ]
  assert_output --partial "ERROR"
}

@test "adapter attributes a step deterministically when timestamps tie" {
  # A step-finish inserted before its tool with the SAME time_created: the
  # id tiebreaker must still order the tool before its step-finish, so the
  # step's cost is attributed rather than dropped.
  local db2="${SANDBOX}/tie.db"
  python3 - "${db2}" "${PROJECT_DIR}" <<'PY'
import json, sqlite3, sys, time
db, proj = sys.argv[1], sys.argv[2]
c = sqlite3.connect(db)
c.executescript(
    "CREATE TABLE session(id TEXT PRIMARY KEY, directory TEXT, time_created INTEGER, time_updated INTEGER);"
    "CREATE TABLE part(id TEXT PRIMARY KEY, message_id TEXT, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);"
)
now = int(time.time() * 1000)
c.execute("INSERT INTO session VALUES('ses1', ?, ?, ?)", (proj, now, now))
# finish first (lower rowid), tool second — but 'a-tool' < 'z-finish'.
c.execute("INSERT INTO part VALUES('z-finish','m',?,?,?,?)",
          ('ses1', now, now, json.dumps({"type": "step-finish", "cost": 1.0, "tokens": {"total": 100}})))
c.execute("INSERT INTO part VALUES('a-tool','m',?,?,?,?)",
          ('ses1', now, now, json.dumps({"type": "tool", "tool": "demo_foo"})))
c.commit()
c.close()
PY

  export OPENCODE_DB_PATH="${db2}"
  run run_adapter --days=30
  [ "${status}" -eq 0 ]
  echo "${output}" | json "[(t['name'], round(t['cost'],2), t['tokens']) for t in data['tools'] if t['name']=='demo_foo'][0]" | grep -Fqx "('demo_foo', 1.0, 100)"
}

@test "adapter aggregates bash/skill/grep/glob arguments" {
  local db3="${SANDBOX}/args.db"
  python3 - "${db3}" "${PROJECT_DIR}" <<'PY'
import json, sqlite3, sys, time
db, proj = sys.argv[1], sys.argv[2]
c = sqlite3.connect(db)
c.executescript(
    "CREATE TABLE session(id TEXT PRIMARY KEY, directory TEXT, time_created INTEGER, time_updated INTEGER);"
    "CREATE TABLE part(id TEXT PRIMARY KEY, message_id TEXT, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);"
)
now = int(time.time() * 1000)
c.execute("INSERT INTO session VALUES('s1', ?, ?, ?)", (proj, now, now))

def part(i, obj):
    c.execute("INSERT INTO part VALUES(?,?,?,?,?,?)",
              (f"p{i}", "m", "s1", now, now, json.dumps(obj)))

part(1, {"type": "tool", "tool": "bash", "state": {"input": {"command": "cd /x && git status --short"}}})
part(2, {"type": "tool", "tool": "skill", "state": {"input": {"name": "devbot:make-plan"}}})
part(3, {"type": "tool", "tool": "grep", "state": {"input": {"pattern": "foo"}}})
part(4, {"type": "tool", "tool": "glob", "state": {"input": {"pattern": "**/*.bats"}}})
c.commit()
c.close()
PY

  export OPENCODE_DB_PATH="${db3}"
  run run_adapter --days=30
  [ "${status}" -eq 0 ]
  # leading `cd … &&` stripped, then first two tokens
  echo "${output}" | json "[(e['value'], e['count']) for e in data['tool_arguments']['bash']]" | grep -Fqx "[('git status', 1)]"
  echo "${output}" | json "[(e['value'], e['count']) for e in data['tool_arguments']['skill']]" | grep -Fqx "[('devbot:make-plan', 1)]"
  echo "${output}" | json "[(e['value'], e['count']) for e in data['tool_arguments']['grep']]" | grep -Fqx "[('foo', 1)]"
  echo "${output}" | json "[(e['value'], e['count']) for e in data['tool_arguments']['glob']]" | grep -Fqx "[('**/*.bats', 1)]"
}
