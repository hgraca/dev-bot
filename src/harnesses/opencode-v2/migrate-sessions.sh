#!/usr/bin/env bash
# =============================================================================
# src/harnesses/opencode-v2/migrate-sessions.sh
# Re-copy the OpenCode 1.x session store into the 2.x store, as often as needed.
#
# 1.x writes session/message/part; 2.x reads session_v2/session_message. The two
# stores are parallel, so a session created on one host is invisible to the
# other. This refreshes the 2.x copy from 1.x.
#
# Usage:
#   migrate-sessions.sh                 # drop migrated rows, re-copy them
#   migrate-sessions.sh --purge         # wipe the whole 2.x store, re-copy 1.x
#   migrate-sessions.sh --backup        # copy the database aside first
#   migrate-sessions.sh --dry-run       # report, change nothing
#   migrate-sessions.sh --directory DIR # one project only
#
# --reset (the default) only clears rows whose version is 1.x — the ones this
# script wrote — so sessions created natively on a 2.x host survive. --purge is
# the only mode that can lose 2.x work.
#
# Re-run it as often as you like: it is clear-then-copy, so the result is always
# exactly "the 1.x store, mirrored".
#
# Stop any running 2.x host first — it caches its session list and will not see
# the new rows until it restarts.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../../.." && pwd)"

# shellcheck source=../../_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

DB="$(python3 -c "
import sys
sys.path.insert(0, '${MODULE_DIR}')
from opencode_db import resolve_db_path
print(resolve_db_path())
")"

PURGE=0
BACKUP=0
PASSTHRU=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge) PURGE=1; shift ;;
    --backup) BACKUP=1; shift ;;
    --dry-run) PASSTHRU+=("$1"); shift ;;
    --directory)
      [[ $# -ge 2 ]] || { _fatal "--directory needs a value"; exit 1; }
      PASSTHRU+=("$1" "$2"); shift 2 ;;
    *) _fatal "unknown option: $1"; exit 1 ;;
  esac
done

_header_3 "OpenCode session store: 1.x -> 2.x"

if [[ ! -f "${DB}" ]]; then
  _fatal "database not found at ${DB}"
  exit 1
fi

if [[ ${BACKUP} -eq 1 ]]; then
  ts="$(date +%Y%m%d-%H%M%S)"
  # WAL mode: the -wal file holds committed pages the main file does not.
  cp "${DB}" "${DB}.pre-migrate-${ts}"
  for suffix in -wal -shm; do
    [[ -f "${DB}${suffix}" ]] && cp "${DB}${suffix}" "${DB}${suffix}.pre-migrate-${ts}"
  done
  _ok "backup written beside the database (.pre-migrate-${ts})"
fi

args=(--reset)
[[ ${PURGE} -eq 1 ]] && args+=(--purge)
args+=(${PASSTHRU[@]+"${PASSTHRU[@]}"})

python3 "${MODULE_DIR}/lib/migrate_sessions.py" "${DB}" "${args[@]}"

python3 - "${DB}" <<'PY'
import sqlite3, sys
con = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
v1 = con.execute("select count(*) from session").fetchone()[0]
v2 = con.execute("select count(*) from session_v2").fetchone()[0]
msgs = con.execute("select count(*) from session_message").fetchone()[0]
print(f"  1.x sessions: {v1}   2.x sessions: {v2}   2.x messages: {msgs}")
PY

_ok "Session store refreshed — restart any running 2.x host to see it"
