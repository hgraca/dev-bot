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
