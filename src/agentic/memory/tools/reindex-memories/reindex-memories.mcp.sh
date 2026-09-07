#!/usr/bin/env bash
# ---
# description: Rebuild the memory index in the background (fire-and-forget) using the configured memory-search engine (qmd: cleanup && update [&& embed]; mdctx: incremental build of the project + global indexes). Coalesces concurrent runs via a pidfile. Pass the argument 'status' to check whether a reindex is running without launching one, or 'prune' to run the cheap self-heal (qmd: cleanup && update only, no embed; mdctx: rebuild) for stale deleted-note entries.
# ---
# =============================================================================
# src/agentic/memory/tools/reindex-memories/reindex-memories.mcp.sh
# Rebuilds the memory index using the engine selected by memory_search_provider:
#   - qmd:  qmd cleanup && qmd update [&& qmd embed]  (cleanup prunes orphaned
#           embedding chunks from deleted/moved docs)
#   - mdctx: mdctx build of the project latent index + the global-memories index
#           (incremental + hash-cached; there is no cleanup/embed concept)
# in the background. The engine dispatch isolates each engine's commands and
# selects them on the provider, exactly like search-memories.
#
# 'prune' mode: qmd runs cleanup && update only (no embed — the slow GPU/model
# step); mdctx runs the same build (already embed-free). Invoked as the
# delete→prune self-heal by the harness start scripts (start.sh →
# _devbot_prune_memories_detached): bash-deleted notes stayed searchable
# because neither harness delivers a delete event for external (bash) rm
# (audit-29), so the prune runs at launch — moved from the session.created
# hook (audit-30/31) to start.sh in audit-36 so it fires per launch and the
# engine gets a head start ahead of the MCP fleet boot.
#
# Coalesces concurrent requests via a pidfile: a second invocation while one is
# running reports "in_progress" instead of stacking another job. Honest status:
# "started" means launched — never "ok" before the work actually completes.
# The `status` argument reports running/idle without launching anything.
#
# Activity is logged to the project's .agents/logs/memory-index.log (engine-
# agnostic name shared by qmd and mdctx) when run from a project, else to the
# devbot cache.
# =============================================================================

set -euo pipefail

# Resolve this script's real dir (tools are symlinked into .opencode/tools).
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "${SOURCE}" ]]; do
  DIR="$(cd -P "$(dirname "${SOURCE}")" && pwd)"
  SOURCE="$(readlink "${SOURCE}")"
  [[ "${SOURCE}" != /* ]] && SOURCE="${DIR}/${SOURCE}"
done
SCRIPT_DIR="$(cd -P "$(dirname "${SOURCE}")" && pwd)"

# shellcheck source=../../functions.sh
source "${SCRIPT_DIR}/../../functions.sh"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
LOCK_DIR="$CACHE_DIR/devbot"
PID_FILE="$LOCK_DIR/reindex-memories.pid"
LOCK_FILE="$LOCK_DIR/reindex-memories.lock"

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"reindex-memories","description":"Rebuild the memory index in the background (fire-and-forget) using the configured memory-search engine (qmd: cleanup && update [&& embed]; mdctx: incremental build of the project + global indexes). Coalesces concurrent runs via a pidfile. Pass the argument 'status' to check whether a reindex is running without launching one, or 'prune' to run the cheap self-heal (qmd: cleanup && update only, no embed; mdctx: rebuild) for stale deleted-note entries.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"Optional positional: 'status' to report running/idle without launching; 'prune' to launch the cheap self-heal pass"}}}}
JSON
    exit 0
    ;;
esac

# ── Engine dispatch ──────────────────────────────────────────────────────────
# The selected engine's binary must exist (qmd | mdctx per
# memory_search_provider). Fail-open semantics unchanged: nothing runs without
# the engine.
PROJECT_DIR="${PWD}"
PROVIDER="$(_devbot_get_memory_search_provider "${PROJECT_DIR}")"
if [[ "${PROVIDER}" == "mdctx" ]]; then
  if ! command -v mdctx >/dev/null 2>&1; then
    echo "FATAL: mdctx binary not found in PATH" >&2
    exit 1
  fi
else
  if ! command -v qmd >/dev/null 2>&1; then
    echo "FATAL: qmd binary not found in PATH" >&2
    exit 1
  fi
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

MODE="full"
if [[ "${1:-}" == "prune" ]]; then
  MODE="prune"
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
# audit-25 F2: flock(1) is util-linux (Linux-only) — macOS lacks it. Fall back
# to python fcntl on the inherited fd 200: the lock lives on the open file
# description, so it is still released when this shell exits (audit-24
# check-then-launch semantics preserved).
if ! { flock -n 200 2>/dev/null || python3 -c 'import fcntl; fcntl.flock(200, fcntl.LOCK_EX|fcntl.LOCK_NB)' 2>/dev/null; }; then
  echo "{\"status\":\"in_progress\",\"pid\":$(cat "$PID_FILE" 2>/dev/null || echo null)}"
  exit 0
fi

if _reindex_running; then
  echo "{\"status\":\"in_progress\",\"pid\":$(cat "$PID_FILE" 2>/dev/null || echo null)}"
  exit 0
fi

rm -f "$PID_FILE"

# ── Background job log (audit-49 NOTE-2) ─────────────────────────────────────
# The background job used to discard the engine's output to /dev/null, so a
# slow or failed reindex was unobservable (a passive reindex was watched take
# ~10 min with no log trail and no completion marker). Log the job to the
# project's .agents/logs/memory-index.log when run from a project (hooks and
# the MCP servers run the tool with the project as cwd), else to the devbot
# cache. The log name is engine-agnostic — shared by qmd and mdctx.
BG_LOG=""
if [[ -d "$PWD/.agents" ]]; then
  mkdir -p "$PWD/.agents/logs" 2>/dev/null || true
  BG_LOG="$PWD/.agents/logs/memory-index.log"
else
  mkdir -p "$LOCK_DIR" 2>/dev/null || true
  BG_LOG="$LOCK_DIR/reindex-memories.log"
fi

if [[ "${PROVIDER}" == "mdctx" ]]; then
  # mdctx has no cleanup/embed distinction: prune and full both run the same
  # incremental build (already embed-free), so the mode does not change the
  # message. The qmd branch below keeps the distinction.
  bg_message="mdctx build (project + global indexes) launched in background"
  DEVBOT_DIR="$(_devbot_get_project_dir "${PROJECT_DIR}")"
  LATENT_DIR="${PROJECT_DIR}/${DEVBOT_DIR}/memory/latent"
  GLOBAL_DIR="${DEV_BOT_ROOT}/storage/global-memories"
  PROJECT_INDEX="${PROJECT_DIR}/.mdctx/context-index.json"
  GLOBAL_INDEX="${DEV_BOT_ROOT}/storage/.mdctx/context-index.json"
else
  # `qmd cleanup` first prunes orphaned embedding chunks (stale vectors from
  # deleted/moved docs) so they don't silently accumulate across sessions
  # (audit-20 FAIL: 135 orphaned chunks, 14%). Best-effort: a cleanup failure
  # must not block the reindex. Prune mode skips embed — see header.
  if [[ "${MODE}" == "prune" ]]; then
    bg_message="qmd cleanup && qmd update (prune, no embed) launched in background"
  else
    bg_message="qmd cleanup && qmd update && qmd embed launched in background"
  fi
fi

# The job runs with errexit OFF: the tool itself is `set -e`, and an inherited
# errexit would abort the subshell on the first failing step BEFORE it removes
# the pid file — leaking the pid and wedging the tool into perpetual
# in_progress (audit-49 NOTE-2). Record and log each step's exit code instead.
(
  set +e
  {
    echo "[reindex-memories] ${MODE} start $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if [[ "${PROVIDER}" == "mdctx" ]]; then
      # mdctx: rebuild the project latent index (when the vault exists) and the
      # global-memories index. Both are incremental + hash-cached.
      _project_rc=1
      if [[ -d "${LATENT_DIR}" ]]; then
        mkdir -p "$(dirname "${PROJECT_INDEX}")"
        mdctx build "${LATENT_DIR}" -o "${PROJECT_INDEX}"
        _project_rc=$?
      else
        _project_rc=0
      fi
      _global_rc=1
      if [[ -d "${GLOBAL_DIR}" ]]; then
        mkdir -p "$(dirname "${GLOBAL_INDEX}")"
        mdctx build "${GLOBAL_DIR}" -o "${GLOBAL_INDEX}"
        _global_rc=$?
      else
        _global_rc=0
      fi
      echo "[reindex-memories] ${MODE} finished project_rc=${_project_rc} global_rc=${_global_rc} $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    else
      qmd cleanup
      _cleanup_rc=$?
      if [[ "${MODE}" == "prune" ]]; then
        qmd update
      else
        qmd update && qmd embed
      fi
      _reindex_rc=$?
      echo "[reindex-memories] ${MODE} finished cleanup=${_cleanup_rc} update-embed=${_reindex_rc} $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    fi
  } >> "${BG_LOG}" 2>&1
  rm -f "$PID_FILE"
) &
bg_pid=$!
echo "$bg_pid" > "$PID_FILE"
disown "$bg_pid" 2>/dev/null || true

echo "{\"status\":\"started\",\"message\":\"${bg_message}\",\"pid\":$bg_pid}"
