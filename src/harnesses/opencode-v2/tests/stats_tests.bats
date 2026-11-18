#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode-v2/tests/stats_tests.bats
# Tests the v2 stats adapter against a synthetic opencode database.
#
# The adapter must emit the canonical `devbot stats` JSON (schema v1) and count
# ONLY 2.x sessions — session_v2 is a shared table that also holds 1.x rows.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"

  WORK="$(mktemp -d)"
  export OPENCODE_DB_PATH="${WORK}/opencode.db"

  python3 - "${OPENCODE_DB_PATH}" <<'PY'
import json, sqlite3, sys, time
now = int(time.time() * 1000)
con = sqlite3.connect(sys.argv[1])
con.execute(
    "create table session_v2 (id text primary key, directory text, version text, time_updated integer)"
)
con.execute("create table session_message (session_id text, type text, seq integer, data text)")
rows = [("ses_v1", "/proj", "1.18.35", now), ("ses_v2", "/proj", "2.3.0", now)]
con.executemany("insert into session_v2 values (?,?,?,?)", rows)

assistant = {
    "content": [
        {"type": "text", "text": "done"},
        {"type": "tool", "name": "shell", "state": {"status": "completed"}},
        {"type": "tool", "name": "read", "state": {"status": "completed"}},
    ],
    "cost": 0.02,
    "tokens": {"input": 100, "output": 20, "reasoning": 0},
}
for session in ("ses_v1", "ses_v2"):
    con.execute(
        "insert into session_message values (?,?,?,?)",
        (session, "assistant", 0, json.dumps(assistant)),
    )
con.commit()
con.close()
PY
}

teardown() {
  rm -rf "${WORK}"
}

run_stats() {
  (cd "${WORK}" && python3 "${MODULE_DIR}/stats.py" "$@")
}

@test "emits the canonical schema-v1 envelope" {
  run run_stats --days 30
  assert_success
  python3 - "$output" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
for key in ("schema", "harness", "days", "scope", "scope_label",
            "generated_at", "cost_kind", "tools", "mcp_servers"):
    assert key in data, f"missing {key}"
assert data["schema"] == 1
assert data["harness"] == "opencode-v2"
assert data["cost_kind"] == "estimated"
PY
}

@test "counts only 2.x sessions, not the 1.x rows in session_v2" {
  run run_stats --days 30 --all
  assert_success
  python3 - "$output" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data["sessions"] == 1, data["sessions"]
assert data["messages"] == 1, data["messages"]
names = sorted(t["name"] for t in data["tools"])
assert names == ["read", "shell"], names
PY
}

@test "filters to the current project when --all is absent" {
  run run_stats --days 30
  assert_success
  python3 - "$output" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data["scope"] == "current"
# The fixture's sessions live in /proj, so a run from WORK matches nothing.
assert data["sessions"] == 0, data["sessions"]
PY
}

@test "reports no sessions outside the window" {
  run run_stats --days 0 --all
  assert_success
  python3 - "$output" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data["sessions"] == 0, data["sessions"]
assert data["tools"] == [], data["tools"]
PY
}

@test "accepts --project and scopes the report to it" {
  # bin/stats.sh always passes --project for a project-scoped report.
  run run_stats --days 30 --project /proj
  assert_success
  python3 - "$output" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data["scope"] == "current", data["scope"]
assert data["sessions"] > 0, data["sessions"]
PY
}

@test "a supported source-build host's sessions are counted" {
  # The version guard allows 0.0.0--<ts> source builds, so the report must too.
  python3 - "${OPENCODE_DB_PATH}" <<'PY'
import sqlite3, sys, time
now = int(time.time() * 1000)
con = sqlite3.connect(sys.argv[1])
con.execute(
    "insert into session_v2 values ('ses_src','/proj','0.0.0--20261016120000',?)", (now,)
)
con.commit()
PY
  run run_stats --days 30 --project /proj
  assert_success
  python3 - "$output" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data["sessions"] == 2, data["sessions"]
PY
}

@test "aggregates MCP servers from recorded tool names" {
  local mcpdir="${BATS_TEST_TMPDIR}/mcpproj"
  local mcpdb="${BATS_TEST_TMPDIR}/mcp.db"
  mkdir -p "$mcpdir"
  cat > "$mcpdir/opencode.jsonc" <<'JSON'
{
  "mcp": {
    "servers": {
      "devbot-tools": { "type": "local", "command": ["bash"] },
      "mdctx": { "type": "remote", "url": "http://127.0.0.1:18501/mcp" },
      "websearch": { "type": "remote", "url": "https://mcp.exa.ai/mcp" }
    }
  }
}
JSON
  python3 - "$mcpdb" "$mcpdir" <<'PY'
import json, sqlite3, sys, time
db, project = sys.argv[1], sys.argv[2]
now = int(time.time() * 1000)
con = sqlite3.connect(db)
con.execute("create table session_v2 (id text primary key, directory text, version text, time_updated integer)")
con.execute("create table session_message (session_id text, type text, seq integer, data text)")
con.execute("insert into session_v2 values (?,?,?,?)", ("ses_mcp", project, "2.3.0", now))
assistant = {
    "content": [
        {"type": "tool", "name": "devbot-tools_search-memories", "state": {"status": "completed"}},
        {"type": "tool", "name": "devbot-tools_tree", "state": {"status": "completed"}},
        {"type": "tool", "name": "mdctx_search_context", "state": {"status": "completed"}},
        {"type": "tool", "name": "shell", "state": {"status": "completed"}},
        # Native tool whose name equals a configured server (websearch is both).
        {"type": "tool", "name": "websearch", "state": {"status": "completed"}},
    ],
    "cost": 0.04,
    "tokens": {"input": 40, "output": 0, "reasoning": 0},
}
con.execute("insert into session_message values (?,?,?,?)", ("ses_mcp", "assistant", 0, json.dumps(assistant)))
con.commit()
con.close()
PY

  run env OPENCODE_DB_PATH="$mcpdb" python3 "${MODULE_DIR}/stats.py" --days 30 --project "$mcpdir"
  assert_success
  python3 - "$output" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
servers = {s["server"]: s for s in data["mcp_servers"]}
assert set(servers) == {"devbot-tools", "mdctx"}, servers
assert servers["devbot-tools"]["count"] == 2, servers["devbot-tools"]
assert servers["mdctx"]["count"] == 1, servers["mdctx"]
assert {t["name"] for t in servers["devbot-tools"]["tools"]} == {"search-memories", "tree"}
assert "shell" not in servers
# A native tool sharing a server name is not an MCP call (audit-02 F-2).
assert "websearch" not in servers
# 40 tokens split across 5 calls: 8 each, 16 for the two devbot-tools calls.
assert servers["devbot-tools"]["tokens"] == 16, servers["devbot-tools"]
PY
}


@test "MCP names are classified against the session's own project" {
  local a="${BATS_TEST_TMPDIR}/proj-a"
  local b="${BATS_TEST_TMPDIR}/proj-b"
  local db="${BATS_TEST_TMPDIR}/two.db"
  mkdir -p "$a" "$b"
  printf '{ "mcp": { "servers": { "alpha": { "type": "local", "command": ["bash"] } } } }\n' > "$a/opencode.jsonc"
  printf '{ "mcp": { "servers": { "beta": { "type": "local", "command": ["bash"] } } } }\n' > "$b/opencode.jsonc"
  python3 - "$db" "$a" "$b" <<'PY'
import json, sqlite3, sys, time
db, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
now = int(time.time() * 1000)
con = sqlite3.connect(db)
con.execute("create table session_v2 (id text primary key, directory text, version text, time_updated integer)")
con.execute("create table session_message (session_id text, type text, seq integer, data text)")
con.execute("insert into session_v2 values (?,?,?,?)", ("ses_a", a, "2.3.0", now))
con.execute("insert into session_v2 values (?,?,?,?)", ("ses_b", b, "2.3.0", now))
def row(sid, name):
    data = {"content": [{"type": "tool", "name": name, "state": {"status": "completed"}}],
            "cost": 0, "tokens": {"input": 0, "output": 0, "reasoning": 0}}
    con.execute("insert into session_message values (?,?,?,?)", (sid, "assistant", 0, json.dumps(data)))
# A session in project A must not claim project B's server name.
row("ses_a", "alpha_search")
row("ses_a", "beta_search")
row("ses_b", "beta_search")
con.commit()
con.close()
PY

  run env OPENCODE_DB_PATH="$db" python3 "${MODULE_DIR}/stats.py" --days 30 --all
  assert_success
  python3 - "$output" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
servers = {s["server"]: s for s in data["mcp_servers"]}
assert set(servers) == {"alpha", "beta"}, servers
assert servers["alpha"]["count"] == 1, servers["alpha"]
assert servers["beta"]["count"] == 1, servers["beta"]
PY
}

@test "a nested session inherits its ancestors' MCP servers" {
  local parent="${BATS_TEST_TMPDIR}/nested-parent"
  local child="${parent}/child"
  local db="${BATS_TEST_TMPDIR}/nested.db"
  mkdir -p "$child"
  printf '{ "mcp": { "servers": { "alpha": { "type": "local", "command": ["bash"] } } } }\n' > "$parent/opencode.jsonc"
  python3 - "$db" "$child" <<'PY'
import json, sqlite3, sys, time
db, project = sys.argv[1], sys.argv[2]
now = int(time.time() * 1000)
con = sqlite3.connect(db)
con.execute("create table session_v2 (id text primary key, directory text, version text, time_updated integer)")
con.execute("create table session_message (session_id text, type text, seq integer, data text)")
con.execute("insert into session_v2 values (?,?,?,?)", ("ses_nested", project, "2.3.0", now))
data = {"content": [{"type": "tool", "name": "alpha_search", "state": {"status": "completed"}}],
        "cost": 0, "tokens": {"input": 0, "output": 0, "reasoning": 0}}
con.execute("insert into session_message values (?,?,?,?)", ("ses_nested", "assistant", 0, json.dumps(data)))
con.commit()
con.close()
PY

  run env OPENCODE_DB_PATH="$db" python3 "${MODULE_DIR}/stats.py" --days 30 --project "$child"
  assert_success
  python3 - "$output" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
servers = {s["server"]: s for s in data["mcp_servers"]}
assert set(servers) == {"alpha"}, servers
assert servers["alpha"]["count"] == 1, servers["alpha"]
PY
}
