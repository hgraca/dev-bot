#!/usr/bin/env bash
# =============================================================================
# src/agentic/memory/tools/reindex-passive-memories.sh
# Passive memory reindex: logs to qmd-index.log and runs
# `qmd cleanup && qmd update && qmd embed` in the background (cleanup first
# prunes orphaned embedding chunks). Extracted from the former opencode hook
# so the logic lives in a tool (shared with the claudecode hook).
#
# Usage: reindex-passive-memories.sh <file> <worktree>
# =============================================================================

set -uo pipefail

FILE="${1:-}"
WORKTREE="${2:-$(pwd)}"

if ! command -v qmd >/dev/null 2>&1; then
  exit 0
fi

LOGS_DIR="${WORKTREE}/.agents/logs"
LOG_FILE="${LOGS_DIR}/qmd-index.log"
mkdir -p "${LOGS_DIR}"

# Coalesce with the reindex-memories hook via its shared pidfile: the two
# memory hooks (reindex-memories matches /memory/latent.*, this one matches
# /memory/latent/(global|learnings)) both fire on latent/learnings + global
# edits. Without a lock, concurrent `qmd update` runs race the SQLite index
# and crash with SQLITE_CONSTRAINT_PRIMARYKEY. If a reindex is already
# running, this edit is already covered — skip.
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
LOCK_DIR="$CACHE_DIR/devbot"
PID_FILE="$LOCK_DIR/reindex-memories.pid"
LOCK_FILE="$LOCK_DIR/reindex-memories.lock"

_reindex_running() {
  [[ -f "$PID_FILE" ]] || return 1
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

# ── Atomic check-then-act (audit-24 NOTE-4) ──────────────────────────────────
# The pidfile check-then-write is a TOCTOU window; serialize with flock on a
# dedicated lock file so concurrent memory hooks cannot both launch a job.
mkdir -p "$LOCK_DIR"
exec 200>"${LOCK_FILE}"
if ! flock -n 200; then
  # Another invocation holds the lock — an edit is already being covered.
  exit 0
fi

if _reindex_running; then
  exit 0
fi

ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '[%s] [QMD-INDEX] file=%s cmd="qmd cleanup && qmd update && qmd embed"\n' "${ISO}" "${FILE}" >> "${LOG_FILE}"
# `qmd cleanup` first prunes orphaned embedding chunks (stale vectors from
# deleted/moved docs) so they don't silently accumulate across sessions
# (audit-20 FAIL: 135 orphaned chunks, 14%). Best-effort: a cleanup failure
# must not block the reindex.
( qmd cleanup >> "${LOG_FILE}" 2>&1; qmd update && qmd embed >> "${LOG_FILE}" 2>&1; rm -f "$PID_FILE" ) &
bg_pid=$!
echo "$bg_pid" > "$PID_FILE"
disown "$bg_pid" 2>/dev/null || true

exit 0
