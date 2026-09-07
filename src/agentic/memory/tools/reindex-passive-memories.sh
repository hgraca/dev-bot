#!/usr/bin/env bash
# =============================================================================
# src/agentic/memory/tools/reindex-passive-memories.sh
# Passive memory reindex: logs to memory-index.log and runs the configured
# engine's reindex in the background — qmd: `qmd cleanup && qmd update && qmd
# embed` (cleanup first prunes orphaned embedding chunks); mdctx: `mdctx
# build` of the project + global indexes (incremental, no cleanup/embed).
# Extracted from the former opencode hook so the logic lives in a tool (shared
# with the claudecode hook).
#
# The engine dispatch mirrors reindex-memories.mcp.sh and search-memories:
# each engine is isolated and selected by memory_search_provider.
#
# Usage: reindex-passive-memories.sh <file> <worktree>
# =============================================================================

set -uo pipefail

FILE="${1:-}"
WORKTREE="${2:-$(pwd)}"

# Resolve this script's real dir (hooks may invoke it via a symlink).
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "${SOURCE}" ]]; do
  DIR="$(cd -P "$(dirname "${SOURCE}")" && pwd)"
  SOURCE="$(readlink "${SOURCE}")"
  [[ "${SOURCE}" != /* ]] && SOURCE="${DIR}/${SOURCE}"
done
SCRIPT_DIR="$(cd -P "$(dirname "${SOURCE}")" && pwd)"

# shellcheck source=../functions.sh
source "${SCRIPT_DIR}/../functions.sh"

PROVIDER="$(_devbot_get_memory_search_provider "${WORKTREE}")"

if [[ "${PROVIDER}" == "mdctx" ]]; then
  command -v mdctx >/dev/null 2>&1 || exit 0
else
  command -v qmd >/dev/null 2>&1 || exit 0
fi

LOGS_DIR="${WORKTREE}/.agents/logs"
LOG_FILE="${LOGS_DIR}/memory-index.log"
mkdir -p "${LOGS_DIR}"

# Coalesce with the reindex-memories hook via its shared pidfile: the two
# memory hooks (reindex-memories matches /memory/latent.*, this one matches
# /memory/latent/(global|learnings)) both fire on latent/learnings + global
# edits. Without a lock, concurrent reindex runs race the shared index and
# crash (qmd: SQLITE_CONSTRAINT_PRIMARYKEY). If a reindex is already running,
# this edit is already covered — skip.
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
# audit-25 F2: flock(1) is util-linux (Linux-only) — macOS lacks it. Fall back
# to python fcntl on the inherited fd 200: the lock lives on the open file
# description, so it is still released when this shell exits (audit-24
# check-then-act semantics preserved).
if ! { flock -n 200 2>/dev/null || python3 -c 'import fcntl; fcntl.flock(200, fcntl.LOCK_EX|fcntl.LOCK_NB)' 2>/dev/null; }; then
  # Another invocation holds the lock — an edit is already being covered.
  exit 0
fi

if _reindex_running; then
  exit 0
fi

ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [[ "${PROVIDER}" == "mdctx" ]]; then
  printf '[%s] [MEMORY-INDEX] file=%s cmd="mdctx build (project + global indexes)"\n' "${ISO}" "${FILE}" >> "${LOG_FILE}"
  DEVBOT_DIR="$(_devbot_get_project_dir "${WORKTREE}")"
  LATENT_DIR="${WORKTREE}/${DEVBOT_DIR}/memory/latent"
  GLOBAL_DIR="${DEV_BOT_ROOT}/storage/global-memories"
  PROJECT_INDEX="${WORKTREE}/.mdctx/context-index.json"
  GLOBAL_INDEX="${DEV_BOT_ROOT}/storage/.mdctx/context-index.json"
  # mdctx has no cleanup/embed distinction — the build is incremental. The
  # errexit-off subshell guarantees the pid file is removed on failure too.
  (
    if [[ -d "${LATENT_DIR}" ]]; then
      mkdir -p "$(dirname "${PROJECT_INDEX}")"
      mdctx build "${LATENT_DIR}" -o "${PROJECT_INDEX}" >> "${LOG_FILE}" 2>&1
    fi
    if [[ -d "${GLOBAL_DIR}" ]]; then
      mkdir -p "$(dirname "${GLOBAL_INDEX}")"
      mdctx build "${GLOBAL_DIR}" -o "${GLOBAL_INDEX}" >> "${LOG_FILE}" 2>&1
    fi
    rm -f "$PID_FILE"
  ) &
else
  # `qmd cleanup` first prunes orphaned embedding chunks (stale vectors from
  # deleted/moved docs) so they don't silently accumulate across sessions
  # (audit-20 FAIL: 135 orphaned chunks, 14%). Best-effort: a cleanup failure
  # must not block the reindex.
  printf '[%s] [QMD-INDEX] file=%s cmd="qmd cleanup && qmd update && qmd embed"\n' "${ISO}" "${FILE}" >> "${LOG_FILE}"
  ( qmd cleanup >> "${LOG_FILE}" 2>&1; qmd update && qmd embed >> "${LOG_FILE}" 2>&1; rm -f "$PID_FILE" ) &
fi
bg_pid=$!
echo "$bg_pid" > "$PID_FILE"
disown "$bg_pid" 2>/dev/null || true

exit 0
