#!/usr/bin/env bats
# =============================================================================
# src/agentic/devbot/tests/session_usage_tests.bats
# Tests for the session-usage MCP tool entrypoint: metadata, rendering and the
# loud failure when no session id can be resolved.
# =============================================================================

setup() {
  bats_require_minimum_version 1.5.0
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="$MODULE_DIR/tools/session-usage.mcp.sh"

  command -v python3 &>/dev/null || skip "python3 not installed"

  TMP="$(mktemp -d)"
  DB="$TMP/opencode.db"
  CATALOG="$TMP/models.json"

  python3 - "$DB" "$CATALOG" <<'PY'
import json
import sqlite3
import sys

db, catalog = sys.argv[1], sys.argv[2]
conn = sqlite3.connect(db)
conn.executescript(
    """
    CREATE TABLE session (
        id text PRIMARY KEY,
        directory text NOT NULL,
        model text,
        tokens_input integer DEFAULT 0 NOT NULL
    );
    CREATE TABLE part (
        id text PRIMARY KEY,
        session_id text NOT NULL,
        time_created integer NOT NULL,
        data text NOT NULL
    );
    """
)
conn.execute(
    "INSERT INTO session (id, directory, model) VALUES (?, ?, ?)",
    ("ses_fixture", "/project", json.dumps({"id": "deepseek-flash", "providerID": "deepseek"})),
)
conn.execute(
    "INSERT INTO part (id, session_id, time_created, data) VALUES (?, ?, ?, ?)",
    ("prt_1", "ses_fixture", 1000, json.dumps({"type": "step-finish", "tokens": {"total": 277304}})),
)
conn.commit()
conn.close()

with open(catalog, "w", encoding="utf-8") as fh:
    json.dump({"deepseek": {"models": {"deepseek-flash": {"limit": {"context": 1048576}}}}}, fh)
PY
}

teardown() {
  rm -rf "$TMP" 2>/dev/null || true
}

@test "mcp-meta declares a valid devbot-tools tool" {
  run "$TOOL" mcp-meta
  assert_success
  echo "$output" | python3 -c '
import json, sys
meta = json.load(sys.stdin)
assert meta["name"] == "session-usage", meta
assert "args" in meta["parameters"]["properties"], meta
'
}

@test "reports the context percentage for a session" {
  run env \
    OPENCODE_DB_PATH="$DB" \
    OPENCODE_MODELS_JSON="$CATALOG" \
    DEV_BOT_SESSION_USAGE_HARNESS=opencode \
    "$TOOL" --session ses_fixture

  assert_success
  assert_output --partial "(26.4%)"
  assert_output --partial "ses_fixture"
}

@test "fails loudly when no session id can be resolved" {
  run env \
    -u DEV_BOT_SESSION_ID \
    OPENCODE_DB_PATH="$DB" \
    OPENCODE_MODELS_JSON="$CATALOG" \
    DEV_BOT_SESSION_USAGE_HARNESS=opencode \
    "$TOOL" --project-dir "$TMP"

  assert_failure
  assert_output --partial "ERROR:"
  assert_output --partial "DEV_BOT_SESSION_ID"
}

@test "harness detection honours TOOLS_MCP_PROJECT_DIR" {
  PROJECT="$TMP/project"
  mkdir -p "$PROJECT" "$TMP/claude/-p"
  printf '{"harness":"claudecode"}\n' > "$PROJECT/.devbot.project.jsonc"

  python3 - "$TMP/claude/-p/claude-fix.jsonl" <<'PY'
import json, sys
line = {
    "type": "assistant",
    "sessionId": "claude-fix",
    "message": {
        "model": "claude-opus-5-5",
        "usage": {
            "input_tokens": 5,
            "cache_read_input_tokens": 5,
            "cache_creation_input_tokens": 0,
            "output_tokens": 0,
        },
    },
}
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    fh.write(json.dumps(line) + "\n")
PY

  run env \
    -u DEV_BOT_SESSION_USAGE_HARNESS \
    TOOLS_MCP_PROJECT_DIR="$PROJECT" \
    CLAUDE_PROJECTS_DIR="$TMP/claude" \
    OPENCODE_MODELS_JSON="$CATALOG" \
    "$TOOL" --session claude-fix --json

  assert_success
  assert_output --partial '"harness": "claudecode"'
}
