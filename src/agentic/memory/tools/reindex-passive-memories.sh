#!/usr/bin/env bash
# =============================================================================
# src/agentic/memory/tools/reindex-passive-memories.sh
# Canonical memory-index engine — the single source of truth for reindexing.
#
# Rebuilds the index for the engine selected by memory_search_provider:
#   - qmd:   `qmd cleanup && qmd update`  (BM25-only — no embed; see ADR
#            20260913072905-qmd-bm25-only-no-model-downloads)
#   - mdctx: `mdctx build` of the project memory tree (latent + work + thinking)
#            + the global-memories index (incremental + hash-cached)
#
# Every caller funnels here, so adding a future engine means editing ONE place:
#   - hooks.json (file.edited)                → default (background)
#   - reindex-memories.mcp.sh                 → delegates with the same args
#     (agent MCP tool + the delete→prune self-heal from start.sh)
#   - search-memories.py (at query time)      → --ensure (blocking; no-op when fresh)
#
# Branch awareness: after a successful project-index build the indexed checkout
# is recorded in <project>/<devbot-dir>/logs/memory-index-branch.json as
# {branch, provider, tree_sha, recorded_at}. `--ensure` compares that record
# against the current checkout and rebuilds only when it no longer matches —
# so a search after a branch switch (or a vault-changing pull) never reads a
# stale index. The record is JSON, not .log, on purpose: session-log rotation
# (`_devbot_rotate_session_logs`) moves only *.log, so the record survives.
#
# Modes:
#   (default)        background build (fire-and-forget); coalesces via pidfile
#   prune            alias of the default — the delete→prune self-heal entry
#                    (an incremental rebuild; it is not a separate cheap pass)
#   --sync           foreground build; blocks until done
#   --ensure         build only when the branch record no longer matches; blocks
#   status           report running/idle from the pidfile; never builds
#   --file <path>    triggering file, for the log line only
#   --worktree <dir> project root (default: $PWD)
#   --path <file>    resolve the owning registered project from a touched file;
#                    overrides --worktree when the file is inside one
# =============================================================================

set -uo pipefail

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

# ── Arguments ────────────────────────────────────────────────────────────────

FILE=""
WORKTREE=""
PATH_ARG=""
FINGERPRINT_DIR=""
MODE="full"

while [[ $# -gt 0 ]]; do
  case "$1" in
    # Guard the two-token shifts: `shift 2` with one arg left fails and leaves
    # $1 unchanged, so the loop would spin forever on a valueless flag (an
    # agent-supplied MCP arg can do this).
    --file)
      FILE="${2:-}"
      if (( $# >= 2 )); then shift 2; else shift; fi ;;
    --worktree)
      WORKTREE="${2:-}"
      if (( $# >= 2 )); then shift 2; else shift; fi ;;
    # --path <file>: resolve the owning registered project from a touched file
    # (a supervisor session editing a child's note must reindex that child, not
    # the supervisor). Falls back to --worktree/$PWD when unresolved.
    --path)
      PATH_ARG="${2:-}"
      if (( $# >= 2 )); then shift 2; else shift; fi ;;
    --fingerprint)
      FINGERPRINT_DIR="${2:-}"
      if (( $# >= 2 )); then shift 2; else shift; fi ;;
    --sync) MODE="sync"; shift ;;
    --ensure) MODE="ensure"; shift ;;
    prune) MODE="prune"; shift ;;
    status) MODE="status"; shift ;;
    *) shift ;;
  esac
done

if ! WORKTREE="$(cd "${WORKTREE:-$(pwd)}" 2>/dev/null && pwd -P)"; then
  WORKTREE="$(pwd -P)"
fi

# --path <file> retargets the reindex to the owning project of a touched file
# (a supervisor editing a child's note). But when the file's owning project is
# the session worktree itself or an ancestor of it, the worktree is the right
# checkout — a linked worktree at <project>/<devbot_dir>/worktrees/<slug> has
# its own vault and index, so reindex that, never the main checkout.
if [[ -n "${PATH_ARG}" ]]; then
  RESOLVED="$(_devbot_resolve_project_for_path "${PATH_ARG}" "${WORKTREE}")"
  RESOLVED="$(cd "${RESOLVED}" 2>/dev/null && pwd -P || printf '%s' "${RESOLVED}")"
  case "${WORKTREE}" in
    "${RESOLVED}" | "${RESOLVED}"/*) ;;
    *) WORKTREE="${RESOLVED}" ;;
  esac
fi

# ── Engine dispatch ──────────────────────────────────────────────────────────
# An engine is selected, never both. The selected engine's binary must exist:
# a missing engine is a FATAL (the MCP tool relies on the loud failure; hooks
# route it to memory-index.log, exactly as the previous .mcp.sh hook did).
PROVIDER="$(_devbot_get_memory_search_provider "${WORKTREE}")"
if [[ "${PROVIDER}" == "mdctx" ]]; then
  ENGINE_BIN="mdctx"
else
  ENGINE_BIN="qmd"
fi
if ! command -v "${ENGINE_BIN}" >/dev/null 2>&1; then
  _fatal "${ENGINE_BIN} binary not found in PATH"
  exit 1
fi

# ── Paths ────────────────────────────────────────────────────────────────────

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
LOCK_DIR="$CACHE_DIR/devbot"
PID_FILE="$LOCK_DIR/reindex-memories.pid"
LOCK_FILE="$LOCK_DIR/reindex-memories.lock"

DEVBOT_DIR="$(_devbot_get_project_dir "${WORKTREE}")"
DEVBOT_STATE_DIR="${WORKTREE}/${DEVBOT_DIR}"
MEMORY_DIR="${DEVBOT_STATE_DIR}/memory"
LOGS_DIR="${DEVBOT_STATE_DIR}/logs"
GLOBAL_DIR="${DEV_BOT_ROOT}/storage/global-memories"
PROJECT_INDEX="${WORKTREE}/.mdctx/context-index.json"
GLOBAL_INDEX="${DEV_BOT_ROOT}/storage/.mdctx/context-index.json"
LOG_FILE="${LOGS_DIR}/memory-index.log"
BRANCH_RECORD="${LOGS_DIR}/memory-index-branch.json"

# Coalesce concurrent reindex requests via this shared pidfile: the file.edited
# hook, the MCP tool and the query-time --ensure all funnel here. Without the
# lock, concurrent runs would race the shared index and crash (qmd:
# SQLITE_CONSTRAINT_PRIMARYKEY). A run already in flight means "covered".
_reindex_running() {
  [[ -f "$PID_FILE" ]] || return 1
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

# ── status ───────────────────────────────────────────────────────────────────

if [[ "${MODE}" == "status" ]]; then
  if _reindex_running; then
    echo "{\"status\":\"in_progress\",\"pid\":$(cat "$PID_FILE" 2>/dev/null || echo null)}"
  else
    echo '{"status":"idle","message":"no reindex in progress"}'
  fi
  exit 0
fi

# ── Branch record ────────────────────────────────────────────────────────────

_current_branch() {
  git -C "${WORKTREE}" rev-parse --abbrev-ref HEAD 2>/dev/null || true
}

# Tree object of the committed vault — changes only when committed vault content
# changes, so an unrelated commit on the same branch never invalidates the index.
_current_vault_tree_sha() {
  local root rel
  root="$(git -C "${WORKTREE}" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "${root}" ]] || return 0
  rel="${WORKTREE#"${root}"}"
  rel="${rel#/}"
  rel="${rel:+${rel}/}${DEVBOT_DIR}/memory"
  git -C "${root}" rev-parse "HEAD:${rel}" 2>/dev/null || true
}

# On-disk corpus fingerprint. The branch record's committed tree sha cannot see
# gitignored work/thinking notes, so a move or deletion there would leave the
# index looking current. Path + size + mtime catches moves, edits and deletes.
_current_corpus_fingerprint() {
  local root="${1:-${MEMORY_DIR}}"
  python3 - "${root}" <<'PY'
import hashlib
import os
import sys

root = sys.argv[1]
digest = hashlib.sha256()
if os.path.isdir(root):
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        dirnames.sort()
        for name in sorted(filenames):
            if not name.endswith((".md", ".mdx")):
                continue
            path = os.path.join(dirpath, name)
            if os.path.islink(path):
                continue
            stat = os.stat(path)
            digest.update(os.path.relpath(path, root).encode())
            digest.update(b"\0")
            digest.update(str(stat.st_size).encode())
            digest.update(b"\0")
            digest.update(str(stat.st_mtime_ns).encode())
            digest.update(b"\0")
print(digest.hexdigest())
PY
}

if [[ -n "${FINGERPRINT_DIR}" ]]; then
  _current_corpus_fingerprint "${FINGERPRINT_DIR}"
  exit 0
fi

# Emit the record JSON on stdout. json.dump escapes the values: git ref names
# may contain characters raw interpolation would break on (a double quote is
# accepted by check-ref-format), producing a malformed or spoofed record.
_emit_record_json() {
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import datetime
import json
import sys

json.dump(
    {
        "branch": sys.argv[1],
        "provider": sys.argv[2],
        "tree_sha": sys.argv[3],
        "corpus": "memory",
        "corpus_fingerprint": sys.argv[4],
        "recorded_at": datetime.datetime.now(datetime.timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
    },
    sys.stdout,
)
print()
PY
}

_record_index_branch() {
  local branch="$1" tree_sha="$2" fingerprint="$3" tmp
  mkdir -p "$(dirname "${BRANCH_RECORD}")" 2>/dev/null || true
  # Write-then-rename: never truncate the live record in place (a concurrent
  # reader could see a torn record, and a symlink planted at the path would be
  # followed). A failed write leaves the previous record intact.
  tmp="${BRANCH_RECORD}.tmp.$$"
  if _emit_record_json "${branch}" "${PROVIDER}" "${tree_sha}" "${fingerprint}" > "${tmp}" 2>/dev/null; then
    mv -f "${tmp}" "${BRANCH_RECORD}" 2>/dev/null || rm -f "${tmp}" 2>/dev/null || true
  fi
}

# Snapshot the checkout BEFORE a build. If HEAD moves while the engine runs, the
# record must describe the tree the index was actually built from — reading it
# after the build would record the new checkout against the old index and make
# --ensure skip the very rebuild this is meant to trigger.
_snapshot_checkout() {
  BUILD_BRANCH="$(_current_branch)"
  BUILD_TREE_SHA="$(_current_vault_tree_sha)"
  BUILD_CORPUS_FP="$(_current_corpus_fingerprint)"
}

# True (exit 0) only when the record matches the current checkout and the qmd
# collection is rooted at the whole memory tree.
_index_record_matches() {
  [[ -f "${BRANCH_RECORD}" ]] || return 1
  if ! python3 - "${BRANCH_RECORD}" "$(_current_branch)" "${PROVIDER}" "$(_current_vault_tree_sha)" "$(_current_corpus_fingerprint)" <<'PY'
import json
import sys

record_path, branch, provider, tree_sha, corpus_fp = sys.argv[1:6]
try:
    record = json.load(open(record_path))
except Exception:
    sys.exit(1)

if record.get("provider") != provider:
    sys.exit(1)
# Records written before the whole-memory corpus carry no corpus marker and
# may describe a latent-only index; force one rebuild so work/thinking appear.
if record.get("corpus") != "memory":
    sys.exit(1)
if record.get("corpus_fingerprint") != corpus_fp:
    sys.exit(1)
if record.get("branch") != branch:
    sys.exit(1)
# An empty tree sha means git could not resolve the vault tree (no repo, or an
# uncommitted vault) — fall back to the branch + provider match alone.
if tree_sha and record.get("tree_sha") != tree_sha:
    sys.exit(1)
sys.exit(0)
PY
  then
    return 1
  fi
  if [[ "${PROVIDER}" == "qmd" ]]; then
    local collection_name collection_root
    collection_name="$(_project_collection_name)"
    collection_root="$(qmd collection show "${collection_name}" 2>/dev/null | awk '/^[[:space:]]*Path:/{sub(/^[[:space:]]*Path:[[:space:]]*/, ""); print; exit}')" || return 1
    [[ "${collection_root}" == "${MEMORY_DIR}" ]]
  fi
}

# ── qmd collection migration ─────────────────────────────────────────────────
# Before the whole-memory scope, qmd collections were rooted at memory/latent.
# Updating such a collection keeps work/thinking/active unsearchable, so move
# it to the memory root before the rebuild. The collection name matches
# search-memories' resolve_collection: project_name or the directory basename.
_project_collection_name() {
  local name=""
  local config="${WORKTREE}/.devbot.project.jsonc"
  if [[ -f "${config}" ]]; then
    name="$(python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${config}" project_name 2>/dev/null || true)"
  fi
  [[ -n "${name}" ]] || name="$(basename "${WORKTREE}")"
  printf '%s' "${name}"
}

_migrate_qmd_collection() {
  [[ -d "${MEMORY_DIR}" ]] || return 0
  local name current_path old_path
  name="$(_project_collection_name)"
  if ! qmd collection show "${name}" >/dev/null 2>&1; then
    echo "[reindex-memories] registering collection ${name} at ${MEMORY_DIR}"
    qmd collection add "${MEMORY_DIR}" --name "${name}" >/dev/null 2>&1 || return 1
    current_path="$(qmd collection show "${name}" 2>/dev/null | awk '/^[[:space:]]*Path:/{sub(/^[[:space:]]*Path:[[:space:]]*/, ""); print; exit}')"
    [[ "${current_path}" == "${MEMORY_DIR}" ]] || return 1
    return 0
  fi
  current_path="$(qmd collection show "${name}" 2>/dev/null | awk '/^[[:space:]]*Path:/{sub(/^[[:space:]]*Path:[[:space:]]*/, ""); print; exit}')"
  if [[ -z "${current_path}" ]]; then
    echo "ERROR: qmd collection ${name} has no readable root path" >&2
    return 1
  fi
  [[ "${current_path}" != "${MEMORY_DIR}" ]] || return 0
  if [[ "${current_path}" != "${MEMORY_DIR}/latent" ]]; then
    echo "ERROR: collection ${name} is registered at ${current_path}, not this checkout's ${MEMORY_DIR}; refusing to repoint (name collision)" >&2
    return 1
  fi
  old_path="${current_path}"
  echo "[reindex-memories] migrating collection ${name}: ${current_path} -> ${MEMORY_DIR}"
  qmd collection remove "${name}" >/dev/null 2>&1 || return 1
  if ! qmd collection add "${MEMORY_DIR}" --name "${name}" >/dev/null 2>&1; then
    qmd collection add "${old_path}" --name "${name}" >/dev/null 2>&1 || true
    return 1
  fi
  # Confirm the root actually moved before the rebuild and the corpus marker.
  current_path="$(qmd collection show "${name}" 2>/dev/null | awk '/^[[:space:]]*Path:/{sub(/^[[:space:]]*Path:[[:space:]]*/, ""); print; exit}')"
  [[ "${current_path}" == "${MEMORY_DIR}" ]] && return 0
  qmd collection remove "${name}" >/dev/null 2>&1 || true
  qmd collection add "${old_path}" --name "${name}" >/dev/null 2>&1 || true
  return 1
}

# ── Engine build ─────────────────────────────────────────────────────────────

# Runs the selected engine's build. Sets PROJECT_BUILD_RC (project index build)
# plus GLOBAL_BUILD_RC (mdctx global store) / CLEANUP_BUILD_RC (qmd cleanup).
# Engine output goes to stdout/stderr — callers redirect it to the log.
_engine_build() {
  PROJECT_BUILD_RC=0
  GLOBAL_BUILD_RC=0
  CLEANUP_BUILD_RC=0
  if [[ "${PROVIDER}" == "mdctx" ]]; then
    if [[ -d "${MEMORY_DIR}" ]]; then
      mkdir -p "$(dirname "${PROJECT_INDEX}")"
      mdctx build "${MEMORY_DIR}" -o "${PROJECT_INDEX}"
      PROJECT_BUILD_RC=$?
    fi
    if [[ -d "${GLOBAL_DIR}" ]]; then
      mkdir -p "$(dirname "${GLOBAL_INDEX}")"
      mdctx build "${GLOBAL_DIR}" -o "${GLOBAL_INDEX}"
      GLOBAL_BUILD_RC=$?
    fi
  else
    if ! _migrate_qmd_collection; then
      echo "ERROR: qmd collection migration failed — refusing to record a memory-corpus index" >&2
      PROJECT_BUILD_RC=1
      return 1
    fi
    qmd cleanup
    CLEANUP_BUILD_RC=$?
    qmd update
    PROJECT_BUILD_RC=$?
  fi
}

# Engine-neutral exit-code suffix for the log's "finished" marker.
_engine_rc_suffix() {
  if [[ "${PROVIDER}" == "mdctx" ]]; then
    printf 'project_rc=%s global_rc=%s' "${PROJECT_BUILD_RC}" "${GLOBAL_BUILD_RC}"
  else
    printf 'cleanup=%s update=%s' "${CLEANUP_BUILD_RC}" "${PROJECT_BUILD_RC}"
  fi
}

# Records the checkout the build started from, only when the project index was
# actually rebuilt.
_record_if_built() {
  [[ "${PROJECT_BUILD_RC}" == "0" ]] || return 0
  [[ -d "${MEMORY_DIR}" ]] || return 0
  _record_index_branch "${BUILD_BRANCH}" "${BUILD_TREE_SHA}" "${BUILD_CORPUS_FP}"
}

# ── Foreground build (--sync / --ensure) ─────────────────────────────────────

# Cap (seconds) to wait for the build lock before giving up.
ENSURE_WAIT="${REINDEX_ENSURE_WAIT:-300}"

# Acquire the build lock. A background build's detached child inherits fd 200,
# so the flock stays held for the whole build — it is the BUILD lock, not just
# a launch lock (verified; the old "released immediately after launch" comment
# was wrong). A foreground build must hold it too, or two engines can write the
# shared index at once (audit-24; qmd: SQLITE_CONSTRAINT_PRIMARYKEY).
_acquire_build_lock() {
  mkdir -p "${LOCK_DIR}" 2>/dev/null || true
  _devbot_lock_wait "${LOCK_FILE}" "${ENSURE_WAIT}" >/dev/null 2>&1
}

# Fail-open with an honest stale status — never build unlocked, never claim
# freshness. The WARN goes to stderr so stdout stays the parseable JSON status
# contract the caller reads; the caller then proceeds on the existing index.
_stale() {
  printf 'WARN: memory index not refreshed (%s)\n' "$1" >&2
  echo "{\"status\":\"stale\",\"reason\":\"$1\"}"
  exit 0
}

_foreground_build() {
  mkdir -p "${LOGS_DIR}" 2>/dev/null || true
  _snapshot_checkout
  _engine_build >> "${LOG_FILE}" 2>&1
  if [[ "${PROJECT_BUILD_RC}" == "0" ]]; then
    _record_if_built
    echo '{"status":"rebuilt"}'
    exit 0
  fi
  printf '[reindex-memories] ensure finished %s\n' "$(_engine_rc_suffix)" \
    >> "${LOG_FILE}" 2>/dev/null || true
  _stale "rebuild-failed"
}

if [[ "${MODE}" == "sync" ]]; then
  [[ -d "${MEMORY_DIR}" ]] || { echo '{"status":"no-vault"}'; exit 0; }
  _acquire_build_lock || _stale "build-lock-timeout"
  _foreground_build
fi

if [[ "${MODE}" == "ensure" ]]; then
  # Fail-open: without a vault there is nothing to index and nothing to record.
  [[ -d "${MEMORY_DIR}" ]] || { echo '{"status":"no-vault"}'; exit 0; }

  if _index_record_matches; then
    echo '{"status":"current"}'
    exit 0
  fi

  # The lock is held for the duration of any in-flight build, so acquiring it
  # both waits for that build and excludes a concurrent one.
  _acquire_build_lock || _stale "build-lock-timeout"
  # Another process may have rebuilt while we waited for the lock.
  if _index_record_matches; then
    echo '{"status":"current"}'
    exit 0
  fi

  _foreground_build
fi

# ── Background build (default / prune) ───────────────────────────────────────

# ── Atomic check-then-act ────────────────────────────────────────────────────
# audit-24 NOTE-4: the pidfile check-then-write below is a TOCTOU window —
# two concurrent invocations could both pass _reindex_running() and both
# launch a job. Serialize the check+launch with an flock on a dedicated lock
# file (the pidfile itself cannot lock: the background job deletes it on
# completion, which would release the lock mid-run). The flock outlives this
# shell: the detached child inherits fd 200 and keeps it held for the whole
# build — this is what lets --ensure/--sync wait for an in-flight job.
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
# slow or failed reindex was unobservable. Log the job to the project's
# memory-index.log when run from a project (hooks and MCP servers run the tool
# with the project as cwd), else to the devbot cache. Engine-agnostic name.
BG_LOG=""
if [[ -d "${DEVBOT_STATE_DIR}" ]]; then
  mkdir -p "${LOGS_DIR}" 2>/dev/null || true
  BG_LOG="${LOG_FILE}"
else
  mkdir -p "${LOCK_DIR}" 2>/dev/null || true
  BG_LOG="${LOCK_DIR}/reindex-memories.log"
fi

if [[ "${PROVIDER}" == "mdctx" ]]; then
  bg_message="mdctx build (project + global indexes) launched in background"
  log_tag="MEMORY-INDEX"
else
  bg_message="qmd cleanup && qmd update launched in background"
  log_tag="QMD-INDEX"
fi

# Triggering-file line, logged before the job so the edit is traceable even if
# the build fails.
if [[ -n "${FILE}" ]]; then
  printf '[%s] [%s] file=%s cmd="%s"\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${log_tag}" "${FILE}" "${bg_message}" \
    >> "${BG_LOG}" 2>/dev/null || true
fi

# The job runs with errexit OFF (explicitly, whatever the invoking shell's
# options): a failing engine step must not abort the subshell BEFORE it removes
# the pid file — that leaks the pid and wedges the tool into perpetual
# in_progress (audit-49 NOTE-2). Record and log each step's exit code instead.
(
  set +e
  {
    echo "[reindex-memories] ${MODE} start $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    _snapshot_checkout
    _engine_build
    _record_if_built
    echo "[reindex-memories] ${MODE} finished $(_engine_rc_suffix) $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >> "${BG_LOG}" 2>&1
  rm -f "$PID_FILE"
) &
bg_pid=$!
echo "$bg_pid" > "$PID_FILE"
disown "$bg_pid" 2>/dev/null || true

echo "{\"status\":\"started\",\"message\":\"${bg_message}\",\"pid\":$bg_pid}"
