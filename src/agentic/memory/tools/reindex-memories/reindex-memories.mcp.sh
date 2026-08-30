#!/usr/bin/env bash
# ---
# description: Rebuild the QMD memory index by running qmd cleanup && qmd update && qmd embed in the background (fire-and-forget). Coalesces concurrent runs via a pidfile. Pass the argument 'status' to check whether a reindex is running without launching one.
# ---
# =============================================================================
# src/agentic/memory/tools/reindex-memories/reindex-memories.mcp.sh
# Rebuilds the QMD memory index (qmd cleanup && qmd update && qmd embed) in the
# background. The cleanup prunes orphaned embedding chunks (stale vectors from
# deleted/moved docs) so they don't silently accumulate across sessions.
#
# Coalesces concurrent requests via a pidfile: a second invocation while one is
# running reports "in_progress" instead of stacking another job. Honest status:
# "started" means launched — never "ok" before the work actually completes.
# The `status` argument reports running/idle without launching anything.
# =============================================================================

set -euo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
LOCK_DIR="$CACHE_DIR/devbot"
PID_FILE="$LOCK_DIR/reindex-memories.pid"
LOCK_FILE="$LOCK_DIR/reindex-memories.lock"

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"reindex-memories","description":"Rebuild the QMD memory index by running qmd cleanup && qmd update && qmd embed in the background (fire-and-forget). Coalesces concurrent runs via a pidfile. Pass the argument 'status' to check whether a reindex is running without launching one.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"Optional positional: 'status' to report running/idle without launching"}}}}
JSON
    exit 0
    ;;
esac

if ! command -v qmd >/dev/null 2>&1; then
  echo "FATAL: qmd binary not found in PATH" >&2
  exit 1
fi

_reindex_running() {
  [[ -f "$PID_FILE" ]] || return 1
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

if [[ "${1:-}" == "status" ]]; then
  if _reindex_running; then
    echo "{\"status\":\"in_progress\",\"pid\":$(cat "$PID_FILE" 2>/dev/null || echo null)}"
  else
    echo '{"status":"idle","message":"no reindex in progress"}'
  fi
  exit 0
fi

# ── Atomic check-then-act ────────────────────────────────────────────────────
# audit-24 NOTE-4: the pidfile check-then-write below is a TOCTOU window —
# two concurrent invocations could both pass _reindex_running() and both
# launch a job. Serialize the check+launch with an flock on a dedicated lock
# file (the pidfile itself cannot lock: the background job deletes it on
# completion, which would release the lock mid-run). The flock fd is closed
# when this shell exits, releasing the lock immediately after launch.
mkdir -p "${LOCK_DIR}"
exec 200>"${LOCK_FILE}"
if ! flock -n 200; then
  echo "{\"status\":\"in_progress\",\"pid\":$(cat "$PID_FILE" 2>/dev/null || echo null)}"
  exit 0
fi

if _reindex_running; then
  echo "{\"status\":\"in_progress\",\"pid\":$(cat "$PID_FILE" 2>/dev/null || echo null)}"
  exit 0
fi

rm -f "$PID_FILE"

# `qmd cleanup` first prunes orphaned embedding chunks (stale vectors from
# deleted/moved docs) so they don't silently accumulate across sessions
# (audit-20 FAIL: 135 orphaned chunks, 14%). Best-effort: a cleanup failure
# must not block the reindex.
( qmd cleanup >/dev/null 2>&1; qmd update && qmd embed; rm -f "$PID_FILE" ) >/dev/null 2>&1 &
bg_pid=$!
echo "$bg_pid" > "$PID_FILE"
disown "$bg_pid" 2>/dev/null || true

echo "{\"status\":\"started\",\"message\":\"qmd cleanup && qmd update && qmd embed launched in background\",\"pid\":$bg_pid}"
