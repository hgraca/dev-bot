#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode-v2/tests/migrate_sessions_tests.bats
# Tests the clear/rollback semantics of the session-store migrator.
#
# The dangerous failure mode is a dry run that deletes: clear() used to commit
# internally, so `--dry-run` wiped the migrated rows before main() rolled back.
# These tests pin "clear does not commit" and "1.x rows only".
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  HELPER="${MODULE_DIR}/lib/migrate_sessions.py"
}

_fixture() {
  local db="$1"
  python3 - "${db}" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.executescript("""
create table session_v2(id text primary key, project_id text, workspace_id text, parent_id text,
  fork_session_id text, fork_boundary text, slug text, directory text, path text, title text,
  version text, share_url text, summary_additions int, summary_deletions int, summary_files int,
  summary_diffs text, metadata text, cost real, tokens_input int, tokens_output int,
  tokens_reasoning int, tokens_cache_read int, tokens_cache_write int, revert text, permission text,
  agent text, model text, time_created int, time_updated int, time_compacting int, time_archived int,
  time_suspended int, resume_attempts int, time_idle int, time_viewed int, idle_outcome text,
  time_busy int);
create table session_message(id text, session_id text, type text, seq int, time_created int,
  time_updated int, data text);
create table session_part(session_id text);
create table session(id text primary key, directory text, time_created int, time_updated int,
  workspace_id text, parent_id text, slug text, path text, title text, version text, share_url text,
  summary_additions int, summary_deletions int, summary_files int, summary_diffs text, metadata text,
  cost real, tokens_input int, tokens_output int, tokens_reasoning int, tokens_cache_read int,
  tokens_cache_write int, revert text, permission text, agent text, model text,
  time_compacting int, time_archived int);
create table message(id text, session_id text, time_created int, time_updated int, data text);
create table part(message_id text, session_id text, time_created int, time_updated int, id text, data text);
create table project(id text primary key, worktree text, vcs text, sandboxes text,
  time_created int, time_updated int);
create table project_directory(project_id text, directory text, type text, time_created int);
insert into session (id, directory, time_created, time_updated, title, version, metadata)
  values ('v1a', '/proj', 1, 2, 'legacy', '1.18.35', '{}');
insert into session (id, directory, time_created, time_updated, title, version, metadata)
  values ('v1b', '/proj', 3, 4, 'other', '1.18.35', '{}');
insert into message values ('m1','v1a',1,2,'{"role":"assistant","model":{"providerID":"p","modelID":"m"}}');
insert into part values ('m1','v1a',1,2,'p1','{"type":"text","text":"hello"}');
insert into session_v2 (id, version) values ('v1a','1.18.35');
insert into session_v2 (id, version) values ('v1b','1.18.35');
insert into session_v2 (id, version) values ('v2a','2.3.0');
insert into session_message (session_id) values ('v1a');
""")
con.commit()
con.close()
PY
}

_count() {
  python3 - "$1" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
print(con.execute("select count(*) from session_v2").fetchone()[0])
PY
}

_call_clear() {
  python3 - "${HELPER}" "$1" "$2" <<'PY'
import importlib.util, sqlite3, sys
spec = importlib.util.spec_from_file_location("m", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
con = sqlite3.connect(sys.argv[2])
removed = m.clear(con, purge=sys.argv[3] == "purge")
if sys.argv[3] == "rollback":
    con.rollback()
else:
    con.commit()
print(removed)
PY
}

@test "clear removes only migrated 1.x rows" {
  db="$(mktemp)"; _fixture "${db}"
  run _call_clear "${db}" commit
  assert_output "2"
  assert_equal "$(_count "${db}")" "1"
  rm -f "${db}"
}

@test "clear does not commit, so a rollback restores every row" {
  db="$(mktemp)"; _fixture "${db}"
  run _call_clear "${db}" rollback
  assert_output "2"
  # The rollback is what makes --dry-run safe.
  assert_equal "$(_count "${db}")" "3"
  rm -f "${db}"
}

@test "clear --purge removes 2.x-native rows too" {
  db="$(mktemp)"; _fixture "${db}"
  python3 - "${HELPER}" "${db}" <<'PY'
import importlib.util, sqlite3, sys
spec = importlib.util.spec_from_file_location("m", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
con = sqlite3.connect(sys.argv[2])
m.clear(con, purge=True)
con.commit()
PY
  assert_equal "$(_count "${db}")" "0"
  rm -f "${db}"
}

@test "dry-run leaves the database untouched end to end" {
  db="$(mktemp)"; _fixture "${db}"
  snapshot() {
    python3 - "$1" <<'SNAP'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
print(con.execute("select count(*) from session_v2").fetchone()[0],
      con.execute("select count(*) from session_message").fetchone()[0])
SNAP
  }
  before="$(snapshot "${db}")"
  run python3 "${HELPER}" "${db}" --reset --dry-run
  assert_success
  assert_equal "$(snapshot "${db}")" "${before}"
  rm -f "${db}"
}

@test "--only-pinned migrates just the pinned sessions" {
  db="$(mktemp)"; _fixture "${db}"
  state="$(mktemp -d)"; mkdir -p "${state}/opencode"
  printf '{"pinned":["v1a"]}\n' > "${state}/opencode/session.json"

  run env XDG_STATE_HOME="${state}" python3 "${HELPER}" "${db}" --purge --only-pinned
  assert_success
  assert_output --partial "pinned sessions: 1"

  run python3 - "${db}" <<'PYX'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
print(",".join(sorted(r[0] for r in con.execute("select id from session_v2"))))
PYX
  assert_output "v1a"

  rm -f "${db}"; rm -r "${state}"
}

@test "--only-pinned with no pinned sessions changes nothing" {
  db="$(mktemp)"; _fixture "${db}"
  state="$(mktemp -d)"; mkdir -p "${state}/opencode"
  printf '{"pinned":[]}\n' > "${state}/opencode/session.json"

  run env XDG_STATE_HOME="${state}" python3 "${HELPER}" "${db}" --purge --only-pinned
  assert_success
  assert_output --partial "nothing to do"
  assert_equal "$(_count "${db}")" "3"

  rm -f "${db}"; rm -r "${state}"
}

@test "a directory-scoped reset clears only that directory's rows" {
  db="$(mktemp)"; _fixture "${db}"
  python3 - "${db}" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute(
    "insert into session (id, directory, time_created, time_updated, title, version, metadata)"
    " values ('v1c', '/other', 5, 6, 'elsewhere', '1.18.35', '{}')"
)
con.execute("insert into session_v2 (id, version) values ('v1c','1.18.35')")
con.commit()
PY
  run python3 - "${HELPER}" "${db}" <<'PY'
import importlib.util, sqlite3, sys
spec = importlib.util.spec_from_file_location("m", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
con = sqlite3.connect(sys.argv[2])
print(m.clear(con, directory="/proj"))
con.commit()
PY
  # v1a and v1b belong to /proj; v1c and the 2.x-native row survive.
  assert_output "2"
  run _count "${db}"
  assert_output "2"
}
