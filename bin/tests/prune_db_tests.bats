#!/usr/bin/env bats
# =============================================================================
# bin/tests/prune_db_tests.bats
# Tests for the opencode SQLite DB prune (`devbot prune --db`):
#
#   src/harnesses/opencode/prune_opencode_db.py — deletes rows older than the
#   cutoff and VACUUMs the file. Sessions cascade to message/part/todo/
#   session_share; the event journal (FK'd to event_sequence, NOT to session) is
#   deleted explicitly, as are orphan journals (no session row); project rows are
#   never age-pruned (session.project_id cascades FROM project).
#
# Run from project root:
#   bats bin/tests/prune_db_tests.bats
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
  PRUNE_SH="${PROJECT_ROOT}/bin/prune.sh"
  HELPER="${PROJECT_ROOT}/src/harnesses/opencode/prune_opencode_db.py"

  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"

  SANDBOX="$(mktemp -d)"
  export OPENCODE_DB_PATH="${SANDBOX}/opencode.db"

  python3 - "${OPENCODE_DB_PATH}" <<'PY'
import sqlite3, sys, time
db = sys.argv[1]
c = sqlite3.connect(db)
c.execute("PRAGMA journal_mode=WAL")  # production is WAL; exercise that path
c.executescript(
    """
    CREATE TABLE project(id TEXT PRIMARY KEY, worktree TEXT NOT NULL,
      time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL);
    CREATE TABLE session(id TEXT PRIMARY KEY, project_id TEXT NOT NULL,
      time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL,
      FOREIGN KEY(project_id) REFERENCES project(id) ON DELETE CASCADE);
    CREATE TABLE message(id TEXT PRIMARY KEY, session_id TEXT NOT NULL,
      time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL,
      FOREIGN KEY(session_id) REFERENCES session(id) ON DELETE CASCADE);
    CREATE TABLE part(id TEXT PRIMARY KEY, message_id TEXT NOT NULL, session_id TEXT NOT NULL,
      time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL,
      FOREIGN KEY(message_id) REFERENCES message(id) ON DELETE CASCADE);
    CREATE TABLE event_sequence(aggregate_id TEXT PRIMARY KEY, seq INTEGER NOT NULL, owner_id TEXT);
    CREATE TABLE event(id TEXT PRIMARY KEY, aggregate_id TEXT NOT NULL, seq INTEGER NOT NULL,
      type TEXT NOT NULL, data TEXT NOT NULL,
      FOREIGN KEY(aggregate_id) REFERENCES event_sequence(aggregate_id) ON DELETE CASCADE);
    CREATE TABLE todo(session_id TEXT NOT NULL, content TEXT NOT NULL, position INTEGER NOT NULL,
      time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL,
      PRIMARY KEY(session_id, position),
      FOREIGN KEY(session_id) REFERENCES session(id) ON DELETE CASCADE);
    CREATE TABLE session_share(session_id TEXT PRIMARY KEY, id TEXT NOT NULL, url TEXT NOT NULL,
      time_created INTEGER NOT NULL,
      FOREIGN KEY(session_id) REFERENCES session(id) ON DELETE CASCADE);
    """
)
now = int(time.time() * 1000)
old = now - 40 * 86400 * 1000
new = now - 1 * 86400 * 1000
blob = "x" * 200000  # forces several pages so VACUUM has something to reclaim

c.execute("INSERT INTO project VALUES('p1','/wt1',?,?)", (now, now))
c.execute("INSERT INTO session VALUES('s-old','p1',?,?)", (old, old))
c.execute("INSERT INTO session VALUES('s-new','p1',?,?)", (new, new))
c.execute("INSERT INTO message VALUES('m-old','s-old',?,?,?)", (old, old, blob))
c.execute("INSERT INTO message VALUES('m-new','s-new',?,?,'{}')", (new, new))
c.execute("INSERT INTO part VALUES('pt-old','m-old','s-old',?,?,?)", (old, old, blob))
c.execute("INSERT INTO part VALUES('pt-new','m-new','s-new',?,?,'{}')", (new, new))
c.execute("INSERT INTO event_sequence VALUES('s-old',1,NULL)")
c.execute("INSERT INTO event_sequence VALUES('s-new',1,NULL)")
for i in range(3):
    c.execute("INSERT INTO event VALUES(?,'s-old',?,'message.part.updated','{}')", (f"e-old-{i}", i))
for i in range(2):
    c.execute("INSERT INTO event VALUES(?,'s-new',?,'message.part.updated','{}')", (f"e-new-{i}", i))
# An orphan journal: a sequence row with no matching session (what opencode's own
# `session delete` leaves behind).
c.execute("INSERT INTO event_sequence VALUES('orphan-agg',1,NULL)")
for i in range(2):
    c.execute("INSERT INTO event VALUES(?,'orphan-agg',?,'message.part.updated','{}')", (f"e-orphan-{i}", i))
c.execute("INSERT INTO todo VALUES('s-old','x',0,?,?)", (old, old))
c.execute("INSERT INTO session_share VALUES('s-old','sh1','https://x',?)", (old,))
c.commit()
c.close()
PY
}

teardown() {
  rm -rf "${SANDBOX}" 2>/dev/null || true
}

_count() {
  python3 -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("SELECT COUNT(*) FROM "+sys.argv[2]).fetchone()[0])' \
    "${OPENCODE_DB_PATH}" "$1"
}

_size() {
  python3 -c 'import os,sys; print(os.path.getsize(sys.argv[1]))' "${OPENCODE_DB_PATH}"
}

# ── Data pruning ──────────────────────────────────────────────────────────────

@test "--db prunes sessions older than the cutoff and keeps recent ones" {
  run bash "${PRUNE_SH}" --db 30 --force
  assert_success
  [ "$(_count session)" -eq 1 ]
}

@test "--db cascades to message/part/todo/session_share" {
  run bash "${PRUNE_SH}" --db 30 --force
  assert_success
  [ "$(_count message)" -eq 1 ]
  [ "$(_count part)" -eq 1 ]
  [ "$(_count todo)" -eq 0 ]
  [ "$(_count session_share)" -eq 0 ]
}

@test "--db prunes the event journal of old sessions and keeps recent events" {
  run bash "${PRUNE_SH}" --db 30 --force
  assert_success
  [ "$(_count event_sequence)" -eq 1 ]
  [ "$(_count event)" -eq 2 ]
}

@test "--db never touches project rows" {
  run bash "${PRUNE_SH}" --db 30 --force
  assert_success
  [ "$(_count project)" -eq 1 ]
}

@test "--db VACUUMs the file so it shrinks" {
  local before after
  before="$(_size)"
  run bash "${PRUNE_SH}" --db 30 --force
  assert_success
  after="$(_size)"
  [ "${after}" -lt "${before}" ]
}

@test "--db is a no-op once nothing aged or orphaned remains" {
  run bash "${PRUNE_SH}" --db 3650 --force   # removes the orphan journal only
  assert_success
  run bash "${PRUNE_SH}" --db 3650 --force   # now genuinely nothing
  assert_success
  assert_output --partial "nothing to prune"
  [ "$(_count session)" -eq 2 ]
}

@test "--db removes orphan journals (no session row) with their events" {
  run bash "${PRUNE_SH}" --db 30 --force
  assert_success
  assert_output --partial "orphan journal(s)"
  [ "$(_count event_sequence)" -eq 1 ]   # only s-new's sequence survives
  [ "$(_count event)" -eq 2 ]
}

@test "--db removes orphan journals even when no session is aged" {
  run bash "${PRUNE_SH}" --db 3650 --force
  assert_success
  assert_output --partial "orphan journals: 1"
  [ "$(_count event_sequence)" -eq 2 ]   # s-old + s-new kept, orphan gone
}

# ── Retention resolution ──────────────────────────────────────────────────────

@test "helper honours DEVBOT_OPENCODE_DB_RETENTION_DAYS when no --days is given" {
  export DEVBOT_OPENCODE_DB_RETENTION_DAYS=0
  run python3 "${HELPER}" --force
  assert_success
  # cutoff = now → every session is older → all pruned
  [ "$(_count session)" -eq 0 ]
}

@test "--db with no <days> and no --force defers to the env default (empty argv)" {
  # pgrep reports opencode NOT running so the guard lets it through.
  mkdir -p "${SANDBOX}/mockbin"
  printf '#!/usr/bin/env bash\nexit 1\n' > "${SANDBOX}/mockbin/pgrep"
  chmod +x "${SANDBOX}/mockbin/pgrep"
  export PATH="${SANDBOX}/mockbin:${PATH}"
  export DEVBOT_OPENCODE_DB_RETENTION_DAYS=0

  run bash "${PRUNE_SH}" --db
  assert_success
  [ "$(_count session)" -eq 0 ]
}

@test "--db handles a WAL-mode database and leaves no WAL behind" {
  local mode
  mode="$(python3 -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("PRAGMA journal_mode").fetchone()[0])' "${OPENCODE_DB_PATH}")"
  [ "${mode}" = "wal" ]

  run bash "${PRUNE_SH}" --db 30 --force
  assert_success
  # wal_checkpoint(TRUNCATE) leaves the sidecar absent or empty
  local wal="${OPENCODE_DB_PATH}-wal"
  [ ! -e "${wal}" ] || [ ! -s "${wal}" ]
  [ "$(_count session)" -eq 1 ]
}

# ── Fail-open on an unreadable/corrupt database (W2/W3) ────────────────────────

@test "helper resolves the DB under XDG_DATA_HOME when OPENCODE_DB_PATH is unset" {
  mkdir -p "${SANDBOX}/xdg/opencode"
  mv "${OPENCODE_DB_PATH}" "${SANDBOX}/xdg/opencode/opencode.db"
  unset OPENCODE_DB_PATH
  export XDG_DATA_HOME="${SANDBOX}/xdg"

  run python3 "${HELPER}" --force
  assert_success
  # Reaching the count proves it found the DB at the XDG path (else "not found").
  assert_output --partial "sessions older than cutoff: 1"
}

@test "helper exits 0 on a schema-less database (fail-open)" {
  python3 -c 'import sqlite3,sys; sqlite3.connect(sys.argv[1]).execute("CREATE TABLE t(x)")' "${OPENCODE_DB_PATH}"
  run python3 "${HELPER}" --force
  assert_success
}

@test "helper exits 0 on a corrupt database file (fail-open)" {
  printf 'this is not a sqlite database' > "${OPENCODE_DB_PATH}"
  run python3 "${HELPER}" --force
  assert_success
}

# ── Guards (fail-open) ────────────────────────────────────────────────────────

@test "--db skips when opencode is running and --force is absent" {
  mkdir -p "${SANDBOX}/mockbin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${SANDBOX}/mockbin/pgrep"
  chmod +x "${SANDBOX}/mockbin/pgrep"
  export PATH="${SANDBOX}/mockbin:${PATH}"

  run bash "${PRUNE_SH}" --db 30
  assert_success
  assert_output --partial "opencode is running"
  [ "$(_count session)" -eq 2 ]
}

@test "helper exits 0 with a WARN when the DB does not exist" {
  export OPENCODE_DB_PATH="${SANDBOX}/absent.db"
  run python3 "${HELPER}" --force
  assert_success
  assert_output --partial "not found"
}
