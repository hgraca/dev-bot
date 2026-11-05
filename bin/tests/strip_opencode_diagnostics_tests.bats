#!/usr/bin/env bats
# =============================================================================
# bin/tests/strip_opencode_diagnostics_tests.bats
# Tests for the diagnostics-blob strip that `devbot prune --db` now runs first:
#
#   src/harnesses/opencode/strip_opencode_diagnostics.py — removes the
#   workspace-wide `state.metadata.diagnostics` map opencode attached to every
#   write/edit tool part (~18 MB per call in a multi-repo checkout), from both
#   `part` and the `event` replay journal, without touching anything else.
#
# Run from project root:
#   bats bin/tests/strip_opencode_diagnostics_tests.bats
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  PROJECT_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
  PRUNE_SH="${PROJECT_ROOT}/bin/prune.sh"
  HELPER="${PROJECT_ROOT}/src/harnesses/opencode/strip_opencode_diagnostics.py"

  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"

  SANDBOX="$(mktemp -d)"
  export OPENCODE_DB_PATH="${SANDBOX}/opencode.db"

  python3 - "${OPENCODE_DB_PATH}" <<'PY'
import json, sqlite3, sys, time

c = sqlite3.connect(sys.argv[1])
c.execute("PRAGMA journal_mode=WAL")  # production is WAL; exercise that path
c.executescript(
    """
    CREATE TABLE session(id TEXT PRIMARY KEY, time_updated INTEGER NOT NULL);
    CREATE TABLE part(id TEXT PRIMARY KEY, session_id TEXT NOT NULL, data TEXT NOT NULL);
    CREATE TABLE event_sequence(aggregate_id TEXT PRIMARY KEY, seq INTEGER NOT NULL, owner_id TEXT);
    CREATE TABLE event(id TEXT PRIMARY KEY, aggregate_id TEXT NOT NULL, seq INTEGER NOT NULL,
      type TEXT NOT NULL, data TEXT NOT NULL,
      FOREIGN KEY(aggregate_id) REFERENCES event_sequence(aggregate_id) ON DELETE CASCADE);
    """
)
now = int(time.time() * 1000)

# The map opencode wrote: one entry per workspace file, nearly all of them empty.
diag = {f"/wt/file{i}.php": [] for i in range(2000)}
diag["/wt/file0.php"] = [{"severity": 1, "message": "boom"}]
diag["/wt/pad.php"] = ["x" * 200000]  # big enough that VACUUM visibly shrinks the file


def tool_part(tool, output, diagnostics=None):
    part = {"type": "tool", "tool": tool, "state": {"status": "completed", "output": output}}
    if diagnostics is not None:
        part["state"]["metadata"] = {"diagnostics": diagnostics, "filepath": "/wt/pad.php"}
    return part


write = tool_part("write", "wrote pad.php", diag)
edit = tool_part("edit", "edited pad.php", diag)
# Output text mentions diagnostics but the part carries no metadata map: the
# cheap candidate scan matches it, and the json_type guard must leave it alone.
false_positive = tool_part("bash", "grep diagnostics /var/log/app.log")

c.execute("INSERT INTO session VALUES('s1',?)", (now,))
c.execute("INSERT INTO event_sequence VALUES('s1',2,NULL)")
for pid, payload in (("p-write", write), ("p-edit", edit), ("p-false", false_positive)):
    c.execute("INSERT INTO part VALUES(?, 's1', ?)", (pid, json.dumps(payload)))
for eid, seq, payload in (
    ("e1", 1, write),
    ("e2", 2, {"type": "text", "text": "hi"}),
):
    c.execute(
        "INSERT INTO event VALUES(?, 's1', ?, 'message.part.updated.1', ?)",
        (eid, seq, json.dumps({"sessionID": "s1", "part": payload})),
    )
c.commit()
c.close()
PY
}

teardown() {
  rm -rf "${SANDBOX}" 2>/dev/null || true
}

_sql() {
  python3 -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute(sys.argv[2]).fetchone()[0])' \
    "${OPENCODE_DB_PATH}" "$1"
}

# Rows still holding the diagnostics map, for a given table and JSON path.
_diag_rows() {
  _sql "SELECT COUNT(*) FROM $1 WHERE json_type(data, '$2') IS NOT NULL"
}

# One JSON field of one row, as text.
_field() {
  python3 -c 'import sqlite3,sys; r=sqlite3.connect(sys.argv[1]).execute(
      "SELECT json_extract(data, ?) FROM " + sys.argv[2] + " WHERE id = ?",
      (sys.argv[4], sys.argv[3])).fetchone(); print("" if r is None else r[0])' \
    "${OPENCODE_DB_PATH}" "$1" "$2" "$3"
}

_size() {
  python3 -c 'import os,sys; print(os.path.getsize(sys.argv[1]))' "${OPENCODE_DB_PATH}"
}

# ── Dry run ───────────────────────────────────────────────────────────────────

@test "dry run reports what it would reclaim and changes nothing" {
  run python3 "${HELPER}" --force
  assert_success
  assert_output --partial "DRY RUN"
  assert_output --partial "reclaimable"
  assert_output --partial "re-run with --apply"
  [ "$(_diag_rows part '$.state.metadata.diagnostics')" -eq 2 ]
  [ "$(_diag_rows event '$.part.state.metadata.diagnostics')" -eq 1 ]
  run bash -c 'ls "${OPENCODE_DB_PATH}".pre-strip-* 2>/dev/null'
  assert_failure
}

# ── Applying ──────────────────────────────────────────────────────────────────

@test "--apply removes the map from part and the event journal, keeping the rest" {
  run python3 "${HELPER}" --apply --force --no-backup --no-vacuum
  assert_success
  [ "$(_diag_rows part '$.state.metadata.diagnostics')" -eq 0 ]
  [ "$(_diag_rows event '$.part.state.metadata.diagnostics')" -eq 0 ]
  # Everything else survives untouched.
  [ "$(_field part p-write '$.state.output')" = "wrote pad.php" ]
  [ "$(_field part p-write '$.state.metadata.filepath')" = "/wt/pad.php" ]
  [ "$(_field part p-write '$.tool')" = "write" ]
  [ "$(_sql "SELECT COUNT(*) FROM part")" -eq 3 ]
  [ "$(_sql "SELECT COUNT(*) FROM event")" -eq 2 ]
}

@test "--apply leaves a part whose text merely mentions diagnostics alone" {
  local before after
  before="$(_sql "SELECT length(data) FROM part WHERE id = 'p-false'")"
  run python3 "${HELPER}" --apply --force --no-backup --no-vacuum
  assert_success
  after="$(_sql "SELECT length(data) FROM part WHERE id = 'p-false'")"
  [ "${before}" = "${after}" ]
  [ "$(_field part p-false '$.state.output')" = "grep diagnostics /var/log/app.log" ]
}

@test "--apply is idempotent" {
  run python3 "${HELPER}" --apply --force --no-backup --no-vacuum
  assert_success
  run python3 "${HELPER}" --apply --force --no-backup --no-vacuum
  assert_success
  assert_output --partial "nothing to strip"
}

@test "--apply VACUUMs, so the file shrinks" {
  local before after
  before="$(_size)"
  run python3 "${HELPER}" --apply --force --no-backup
  assert_success
  assert_output --partial "integrity: ok"
  after="$(_size)"
  [ "${after}" -lt "${before}" ]
}

@test "--apply takes a database copy unless --no-backup is given" {
  run python3 "${HELPER}" --apply --force --no-vacuum
  assert_success
  assert_output --partial "backup:"
  run bash -c 'ls "${OPENCODE_DB_PATH}".pre-strip-*'
  assert_success
  [ "$(_diag_rows part '$.state.metadata.diagnostics')" -eq 0 ]
}

@test "--apply copies the database mode onto the backup" {
  python3 -c 'import os,sys; os.chmod(sys.argv[1], 0o600)' "${OPENCODE_DB_PATH}"
  run python3 "${HELPER}" --apply --force --no-vacuum
  assert_success
  python3 - "${OPENCODE_DB_PATH}" <<'PY'
import glob, os, stat, sys
src = stat.S_IMODE(os.stat(sys.argv[1]).st_mode)
backups = glob.glob(sys.argv[1] + ".pre-strip-*")
assert len(backups) == 1, backups
mode = stat.S_IMODE(os.stat(backups[0]).st_mode)
assert mode == src, (oct(mode), oct(src))
PY
}

# ── Guards (fail-open) ────────────────────────────────────────────────────────

@test "--apply refuses while opencode is running unless --force is given" {
  mkdir -p "${SANDBOX}/mockbin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${SANDBOX}/mockbin/pgrep"
  chmod +x "${SANDBOX}/mockbin/pgrep"
  export PATH="${SANDBOX}/mockbin:${PATH}"

  run python3 "${HELPER}" --apply --no-backup --no-vacuum
  assert_success
  assert_output --partial "refusing"
  [ "$(_diag_rows part '$.state.metadata.diagnostics')" -eq 2 ]
}

@test "helper exits 0 with a WARN when the DB does not exist" {
  export OPENCODE_DB_PATH="${SANDBOX}/absent.db"
  run python3 "${HELPER}" --apply --force
  assert_success
  assert_output --partial "not found"
}

# ── Wiring into `devbot prune --db` ───────────────────────────────────────────

@test "devbot prune --db strips the diagnostics map" {
  run bash "${PRUNE_SH}" --db 3650 --force
  assert_success
  [ "$(_diag_rows part '$.state.metadata.diagnostics')" -eq 0 ]
  [ "$(_diag_rows event '$.part.state.metadata.diagnostics')" -eq 0 ]
  [ "$(_sql "SELECT COUNT(*) FROM session")" -eq 1 ]
}

@test "devbot prune --db reclaims the space even when nothing is aged" {
  local before after
  before="$(_size)"
  run bash "${PRUNE_SH}" --db 3650 --force
  assert_success
  after="$(_size)"
  [ "${after}" -lt "${before}" ]
}

@test "devbot prune --db stays fail-open when a payload is malformed json" {
  # Matches the cheap candidate scan but cannot be parsed, so the strip pass
  # raises inside sqlite; the prune must report and exit 0, not traceback.
  python3 -c 'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute(
      "UPDATE part SET data = ? WHERE id = ?",
      ("{\"state\":{\"metadata\":{\"diagnostics\":", "p-write")); c.commit()' \
    "${OPENCODE_DB_PATH}"

  run bash "${PRUNE_SH}" --db 3650 --force
  assert_success
  assert_output --partial "diagnostics strip aborted"
}

@test "devbot prune --db leaves the false-positive part untouched" {
  run bash "${PRUNE_SH}" --db 3650 --force
  assert_success
  [ "$(_field part p-false '$.state.output')" = "grep diagnostics /var/log/app.log" ]
}
