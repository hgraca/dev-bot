#!/usr/bin/env bash
# =============================================================================
# src/agentic/memory/tools/reindex-passive-memories.sh
# Canonical memory-index engine — the single source of truth for reindexing.
#
# Rebuilds the index for the engine selected by memory_search_provider:
#   - qmd:   `qmd cleanup && qmd update`  (BM25-only — no embed; see ADR
#            20260913072905-qmd-bm25-only-no-model-downloads)
#   - mdctx: `mdctx build` of every configured collection — the project latent
#            corpus, the global store, and custom collections (incremental +
#            hash-cached)
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

# Canonicalize the install root: callers (tests) pass `..`-laden paths and the
# resolver returns canonical ones. Comparisons must not differ by spelling.
DEV_BOT_ROOT="$(cd "${DEV_BOT_ROOT}" 2>/dev/null && pwd -P || printf '%s' "${DEV_BOT_ROOT}")"

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
# The originating session, before --path retargets the build to a child.
SESSION_WORKTREE="${WORKTREE}"

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
LATENT_DIR="${MEMORY_DIR}/latent"
LOGS_DIR="${DEVBOT_STATE_DIR}/logs"
GLOBAL_DIR="${DEV_BOT_ROOT}/storage/global-memories"
PROJECT_INDEX="${WORKTREE}/.mdctx/context-index.json"
GLOBAL_INDEX="${DEV_BOT_ROOT}/storage/.mdctx/context-index.json"
LOG_FILE="${LOGS_DIR}/memory-index.log"
BRANCH_RECORD="${LOGS_DIR}/memory-index-branch.json"

# ── Configured collections ───────────────────────────────────────────────────
# The resolver is the single source of truth shared with search-memories. A
# config error (reserved key, bad shape) aborts before any engine work. The
# status and --fingerprint queries must not depend on the config, so they skip
# this block (and exit before either helper is used).
if [[ -z "${FINGERPRINT_DIR}" && "${MODE}" != "status" ]]; then
  if [[ -f "${DEV_BOT_ROOT}/src/_shared/memory_collections.py" ]]; then
    if ! CHILD_COLLECTIONS_JSON="$(
      python3 "${DEV_BOT_ROOT}/src/_shared/memory_collections.py" \
        --project-root "${WORKTREE}" 2>&1
    )"; then
      printf '%s\n' "${CHILD_COLLECTIONS_JSON}" >&2
      _fatal "memory_collections is invalid"
      exit 1
    fi
    if [[ "${SESSION_WORKTREE}" != "${WORKTREE}" ]]; then
      # A supervisor custom corpus can live under a child project. Resolve the
      # session's customs and keep the child's project slot.
      if ! SESSION_COLLECTIONS_JSON="$(
        python3 "${DEV_BOT_ROOT}/src/_shared/memory_collections.py" \
          --project-root "${SESSION_WORKTREE}" 2>&1
      )"; then
        printf '%s\n' "${SESSION_COLLECTIONS_JSON}" >&2
        _fatal "memory_collections is invalid"
        exit 1
      fi
      if ! COLLECTIONS_JSON="$(
        python3 - "${CHILD_COLLECTIONS_JSON}" "${SESSION_COLLECTIONS_JSON}" <<'PY'
import json
import sys

child = json.loads(sys.argv[1])["collections"]
session = json.loads(sys.argv[2])["collections"]
merged = [c for c in child if c["kind"] == "project"]
merged += [c for c in session if c["kind"] != "project"]
print(json.dumps({"collections": merged}))
PY
      )"; then
        _fatal "could not merge the session and child collection sets"
        exit 1
      fi
    else
      COLLECTIONS_JSON="${CHILD_COLLECTIONS_JSON}"
    fi
  else
    # An old install lacks the resolver: keep the pre-config project + global set.
    FALLBACK_PROJECT_NAME=""
    if [[ -f "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" && -f "${WORKTREE}/.devbot.project.jsonc" ]]; then
      FALLBACK_PROJECT_NAME="$(python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${WORKTREE}/.devbot.project.jsonc" project_name 2>/dev/null || true)"
    fi
    [[ -n "${FALLBACK_PROJECT_NAME}" ]] || FALLBACK_PROJECT_NAME="$(basename "${WORKTREE}")"
    COLLECTIONS_JSON="$(python3 - "${LATENT_DIR}" "${GLOBAL_DIR}" \
      "${PROJECT_INDEX}" "${GLOBAL_INDEX}" "${FALLBACK_PROJECT_NAME}" <<'PY'
import json
import sys

latent, global_dir, project_index, global_index, project_name = sys.argv[1:6]
print(
    json.dumps(
        {
            "collections": [
                {"key": "project", "path": latent, "semantic": False,
                 "physical": project_name, "kind": "project",
                 "source": "default", "exists": True, "index": project_index},
                {"key": "global", "path": global_dir, "semantic": False,
                 "physical": "dev-bot-global", "kind": "global",
                 "source": "default", "exists": True, "index": global_index},
            ]
        }
    )
)
PY
)"
  fi

  # Emit "key<TAB>path<TAB>kind<TAB>semantic<TAB>physical<TAB>index" rows.
  _collection_rows() {
    python3 - "${COLLECTIONS_JSON}" <<'PY'
import json
import sys

seen = set()
for c in json.loads(sys.argv[1])["collections"]:
    # Two logical keys naming the same corpus share one destination; build it
    # once.
    identity = (c["physical"], c["index"])
    if identity in seen:
        continue
    seen.add(identity)
    print(
        "\t".join(
            [
                c["key"],
                c["path"],
                c["kind"],
                "1" if c["semantic"] else "0",
                c["index"],
                c["physical"],
            ]
        )
    )
PY
  }

  # Print one field of the first collection with this key (empty when absent).
  _collection_field() {
    python3 - "${COLLECTIONS_JSON}" "$1" "$2" <<'PY'
import json
import sys

for c in json.loads(sys.argv[1])["collections"]:
    if c["key"] == sys.argv[2]:
        print(c[sys.argv[3]])
        break
PY
  }

  # Any configured corpus present on disk is enough to build.
  _any_collection_exists() {
    python3 - "${COLLECTIONS_JSON}" <<'PY'
import json
import os
import sys

sys.exit(
    0
    if any(
        os.path.isdir(c["path"])
        for c in json.loads(sys.argv[1])["collections"]
    )
    else 1
)
PY
  }

  # Fingerprint of the collection set AND each collection's corpus. Config,
  # destination and content changes (including a custom collection) force a
  # rebuild.
  _collections_fingerprint() {
    python3 - "${COLLECTIONS_JSON}" <<'PY'
import hashlib
import json
import os
import sys

digest = hashlib.sha256()


def add(value):
    digest.update(value.encode() if isinstance(value, str) else value)
    digest.update(b"\0")


for c in sorted(json.loads(sys.argv[1])["collections"], key=lambda x: x["key"]):
    add(c["key"])
    add(c["path"])
    add("1" if c["semantic"] else "0")
    add(c["physical"])
    add(c["index"])
    root = c["path"]
    present = os.path.isdir(root)
    add("1" if present else "0")
    if not present:
        continue
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        dirnames.sort()
        for name in sorted(filenames):
            if not name.endswith((".md", ".mdx")):
                continue
            path = os.path.join(dirpath, name)
            if os.path.islink(path):
                continue
            stat = os.stat(path)
            add(os.path.relpath(path, root))
            add(str(stat.st_size))
            add(str(stat.st_mtime_ns))
print(digest.hexdigest())
PY
  }
fi

# A file.edited hook now fires for every markdown file. An edit outside every
# resolved collection needs no rebuild — skip before taking the build lock.
if [[ -n "${PATH_ARG}" && -n "${COLLECTIONS_JSON:-}" ]]; then
  if ! python3 - "${PATH_ARG}" "${COLLECTIONS_JSON}" <<'PY'
import json
import os
import sys

path = os.path.realpath(sys.argv[1])
roots = [
    os.path.realpath(c["path"]) for c in json.loads(sys.argv[2])["collections"]
]
inside = any(path == root or path.startswith(root + os.sep) for root in roots)
sys.exit(0 if inside else 1)
PY
  then
    echo '{"status":"skipped","reason":"outside-configured-collections"}'
    exit 0
  fi
fi

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
  rel="${rel:+${rel}/}${DEVBOT_DIR}/memory/latent"
  git -C "${root}" rev-parse "HEAD:${rel}" 2>/dev/null || true
}

# On-disk corpus fingerprint. The branch record's committed tree sha cannot see
# gitignored work/thinking notes, so a move or deletion there would leave the
# index looking current. Path + size + mtime catches moves, edits and deletes.
_current_corpus_fingerprint() {
  local root="${1:-${LATENT_DIR}}"
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
  python3 - "$1" "$2" "$3" "$4" "$5" "$6" <<'PY'
import datetime
import json
import sys

json.dump(
    {
        "branch": sys.argv[1],
        "provider": sys.argv[2],
        "tree_sha": sys.argv[3],
        "corpus": "latent",
        "corpus_fingerprint": sys.argv[4],
        "collections_fingerprint": sys.argv[5],
        "project_collection_path": sys.argv[6],
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
  local branch="$1" tree_sha="$2" fingerprint="$3" collections_fp="$4" project_path="$5" tmp
  mkdir -p "$(dirname "${BRANCH_RECORD}")" 2>/dev/null || true
  # Write-then-rename: never truncate the live record in place (a concurrent
  # reader could see a torn record, and a symlink planted at the path would be
  # followed). A failed write leaves the previous record intact.
  tmp="${BRANCH_RECORD}.tmp.$$"
  if _emit_record_json "${branch}" "${PROVIDER}" "${tree_sha}" "${fingerprint}" "${collections_fp}" "${project_path}" > "${tmp}" 2>/dev/null; then
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
  BUILD_COLLECTIONS_FP="$(_collections_fingerprint)"
}

# True (exit 0) only when the record matches the current checkout and the qmd
# collection is rooted at the latent corpus.
_index_record_matches() {
  [[ -f "${BRANCH_RECORD}" ]] || return 1
  if ! python3 - "${BRANCH_RECORD}" "$(_current_branch)" "${PROVIDER}" "$(_current_vault_tree_sha)" "$(_current_corpus_fingerprint)" "$(_collections_fingerprint)" <<'PY'
import json
import sys

record_path, branch, provider, tree_sha, corpus_fp, collections_fp = sys.argv[1:7]
try:
    record = json.load(open(record_path))
except Exception:
    sys.exit(1)

if record.get("provider") != provider:
    sys.exit(1)
# Records written for the whole-memory corpus carry "memory" and describe an
# index that also covers work/ and thinking/; force one rebuild so search stops
# returning them.
if record.get("corpus") != "latent":
    sys.exit(1)
if record.get("corpus_fingerprint") != corpus_fp:
    sys.exit(1)
if record.get("collections_fingerprint") != collections_fp:
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
    local key path kind _ index physical current
    while IFS="$(printf '\t')" read -r key path kind _ index physical; do
      # A missing root is intentional; the fingerprints cover that state.
      [[ -d "${path}" ]] || continue
      current="$(qmd collection show "${physical}" 2>/dev/null | awk '/^[[:space:]]*Path:/{sub(/^[[:space:]]*Path:[[:space:]]*/, ""); print; exit}')" || return 1
      [[ "${current}" == "${path}" ]] || return 1
    done < <(_collection_rows)
  fi
}

# ── qmd collection migration ─────────────────────────────────────────────────
# Collections widened to the whole memory tree are moved back to the latent
# corpus before the rebuild, so work/thinking/active drop out of search. The
# collection name matches search-memories' resolve_collection: project_name or
# the directory basename.
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
  local name current_path old_path released=""
  name="$(_project_collection_name)"
  if [[ ! -d "${LATENT_DIR}" ]]; then
    # Nothing to index. A surviving whole-memory registration would keep
    # work/thinking searchable while the rebuild records the latent corpus, so
    # fail closed instead of silently leaving it in place. Registration is the
    # Path line, the same signal migration reads below.
    if qmd collection show "${name}" 2>/dev/null | grep -q '^[[:space:]]*Path:'; then
      echo "ERROR: collection ${name} is still registered but ${LATENT_DIR} is missing; refusing to record a latent-corpus index" >&2
      return 1
    fi
    return 0
  fi
  if ! qmd collection show "${name}" >/dev/null 2>&1; then
    echo "[reindex-memories] registering collection ${name} at ${LATENT_DIR}"
    released="$(_devbot_release_custom_at_path "${LATENT_DIR}")"
    if ! qmd collection add "${LATENT_DIR}" --name "${name}" >/dev/null 2>&1; then
      _devbot_restore_custom_at_path "${released}" "${LATENT_DIR}"
      return 1
    fi
    current_path="$(qmd collection show "${name}" 2>/dev/null | awk '/^[[:space:]]*Path:/{sub(/^[[:space:]]*Path:[[:space:]]*/, ""); print; exit}')"
    if [[ "${current_path}" != "${LATENT_DIR}" ]]; then
      _devbot_restore_custom_at_path "${released}" "${LATENT_DIR}"
      return 1
    fi
    return 0
  fi
  current_path="$(qmd collection show "${name}" 2>/dev/null | awk '/^[[:space:]]*Path:/{sub(/^[[:space:]]*Path:[[:space:]]*/, ""); print; exit}')"
  if [[ -z "${current_path}" ]]; then
    echo "ERROR: qmd collection ${name} has no readable root path" >&2
    return 1
  fi
  [[ "${current_path}" != "${LATENT_DIR}" ]] || return 0
  if [[ "${current_path}" != "${MEMORY_DIR}" ]]; then
    # Only the whole-memory root (the previous corpus) or this checkout's last
    # recorded root is legitimate. A nested worktree is a descendant of this
    # checkout but has its own record, so a prefix check is not ownership.
    if [[ "${current_path}" != "$(_previous_project_collection_path)" ]]; then
      echo "ERROR: collection ${name} is registered at ${current_path}, not this checkout's ${LATENT_DIR}; refusing to repoint (name collision)" >&2
      return 1
    fi
  fi
  old_path="${current_path}"
  echo "[reindex-memories] migrating collection ${name}: ${current_path} -> ${LATENT_DIR}"
  released="$(_devbot_release_custom_at_path "${LATENT_DIR}")"
  if ! qmd collection remove "${name}" >/dev/null 2>&1; then
    _devbot_restore_custom_at_path "${released}" "${LATENT_DIR}"
    return 1
  fi
  if ! qmd collection add "${LATENT_DIR}" --name "${name}" >/dev/null 2>&1; then
    qmd collection add "${old_path}" --name "${name}" >/dev/null 2>&1 || true
    _devbot_restore_custom_at_path "${released}" "${LATENT_DIR}"
    return 1
  fi
  # Confirm the root actually moved before the rebuild and the corpus marker.
  current_path="$(qmd collection show "${name}" 2>/dev/null | awk '/^[[:space:]]*Path:/{sub(/^[[:space:]]*Path:[[:space:]]*/, ""); print; exit}')"
  [[ "${current_path}" == "${LATENT_DIR}" ]] && return 0
  qmd collection remove "${name}" >/dev/null 2>&1 || true
  qmd collection add "${old_path}" --name "${name}" >/dev/null 2>&1 || true
  _devbot_restore_custom_at_path "${released}" "${LATENT_DIR}"
  return 1
}

# Register a collection at its resolved root, repointing it when the config
# deliberately moved it (built-in path overrides). Custom names embed the
# resolved root in their identity, so a mismatch there is a stale registration.
# Custom-registration release/restore is shared with the init scripts; see
# _devbot_{release,restore}_custom_at_path in src/_shared/functions.sh.

_repoint_qmd_collection() {
  local name="$1" path="$2" owner="${3:-}" current released=""
  if [[ "${name}" != dev-bot-custom-* ]]; then
    released="$(_devbot_release_custom_at_path "${path}")"
  fi
  if ! qmd collection show "${name}" >/dev/null 2>&1; then
    echo "[reindex-memories] registering collection ${name} at ${path}"
    if ! qmd collection add "${path}" --name "${name}" >/dev/null 2>&1; then
      _devbot_restore_custom_at_path "${released}" "${path}"
      return 1
    fi
    return 0
  fi
  current="$(qmd collection show "${name}" 2>/dev/null | awk '/^[[:space:]]*Path:/{sub(/^[[:space:]]*Path:[[:space:]]*/, ""); print; exit}')"
  if [[ -z "${current}" ]]; then
    echo "ERROR: qmd collection ${name} has no readable root path" >&2
    _devbot_restore_custom_at_path "${released}" "${path}"
    return 1
  fi
  [[ "${current}" != "${path}" ]] || return 0
  if [[ -n "${owner}" && "${current}" != "$(_previous_project_collection_path)" ]]; then
    echo "ERROR: collection ${name} is registered outside this checkout (${current}); refusing to repoint" >&2
    _devbot_restore_custom_at_path "${released}" "${path}"
    return 1
  fi
  echo "[reindex-memories] repointing collection ${name}: ${current} -> ${path}"
  if ! qmd collection remove "${name}" >/dev/null 2>&1; then
    _devbot_restore_custom_at_path "${released}" "${path}"
    return 1
  fi
  if ! qmd collection add "${path}" --name "${name}" >/dev/null 2>&1; then
    qmd collection add "${current}" --name "${name}" >/dev/null 2>&1 || true
    _devbot_restore_custom_at_path "${released}" "${path}"
    return 1
  fi
}

# ── Engine build ─────────────────────────────────────────────────────────────

# Runs the selected engine's build. Sets PROJECT_BUILD_RC (project index build)
# plus GLOBAL_BUILD_RC (mdctx global store) / CUSTOM_BUILD_RC (custom
# collections) / CLEANUP_BUILD_RC (qmd cleanup). Engine output goes to
# stdout/stderr — callers redirect it to the log.
_engine_build() {
  PROJECT_BUILD_RC=0
  GLOBAL_BUILD_RC=0
  CUSTOM_BUILD_RC=0
  CLEANUP_BUILD_RC=0
  PROJECT_REGISTERED_PATH=""
  local key path kind physical index rc
  if [[ "${PROVIDER}" == "mdctx" ]]; then
    while IFS="$(printf '\t')" read -r key path kind _ index physical; do
      [[ -d "${path}" ]] || continue
      mkdir -p "$(dirname "${index}")"
      mdctx build "${path}" -o "${index}"
      rc=$?
      case "${kind}" in
        project) PROJECT_BUILD_RC=$rc ;;
        global) GLOBAL_BUILD_RC=$rc ;;
        custom) [[ $rc -eq 0 ]] || CUSTOM_BUILD_RC=$rc ;;
      esac
    done < <(_collection_rows)
  else
    while IFS="$(printf '\t')" read -r key path kind _ index physical; do
      # Migrate the project collection before the missing-path skip below: a
      # surviving whole-memory registration must fail the run, not slip through
      # while qmd cleanup/update keeps indexing work/ and thinking/.
      if [[ "${kind}" == "project" && "${path}" == "${LATENT_DIR}" ]]; then
        if ! _migrate_qmd_collection; then
          echo "ERROR: qmd project collection migration failed — refusing to record a latent-corpus index" >&2
          PROJECT_BUILD_RC=1
        elif [[ -d "${LATENT_DIR}" ]]; then
          PROJECT_REGISTERED_PATH="${path}"
          _persist_project_collection_path "${path}"
        fi
        continue
      fi
      if [[ ! -d "${path}" ]]; then
        echo "WARN: collection ${key} path missing: ${path}" >&2
        continue
      fi
      local owner=""
      [[ "${kind}" == "project" ]] && owner="${WORKTREE}"
      if _repoint_qmd_collection "${physical}" "${path}" "${owner}"; then
        if [[ "${kind}" == "project" ]]; then
          PROJECT_REGISTERED_PATH="${path}"
          _persist_project_collection_path "${path}"
        fi
      else
        CUSTOM_BUILD_RC=$?
      fi
    done < <(_collection_rows)
    [[ "${PROJECT_BUILD_RC}" == "0" ]] || return 1
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
  [[ "${CUSTOM_BUILD_RC:-0}" == "0" ]] || return 0
  [[ "${GLOBAL_BUILD_RC:-0}" == "0" ]] || return 0
  _any_collection_exists || return 0
  local project_path
  project_path="${PROJECT_REGISTERED_PATH:-$(_previous_project_collection_path)}"
  [[ -n "${project_path}" ]] || project_path="$(_collection_field project path)"
  _record_index_branch "${BUILD_BRANCH}" "${BUILD_TREE_SHA}" \
    "${BUILD_CORPUS_FP}" "${BUILD_COLLECTIONS_FP}" "${project_path}"
}

# The project collection path recorded by the last successful build. Used to
# distinguish this project's previous (possibly external) root from another
# checkout's registration of the same collection name.
_previous_project_collection_path() {
  python3 - "${BRANCH_RECORD}" <<'PY'
import json
import sys

try:
    print(json.load(open(sys.argv[1])).get("project_collection_path", ""))
except Exception:
    pass
PY
}

# Persist registration ownership immediately, without touching the freshness
# fingerprints: a failed build must not leave qmd pointing at a root the record
# does not know about.
_persist_project_collection_path() {
  local path="$1"
  mkdir -p "$(dirname "${BRANCH_RECORD}")" 2>/dev/null || true
  python3 - "${BRANCH_RECORD}" "${path}" <<'PY'
import json
import os
import sys

record, path = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(record))
except Exception:
    data = {}
data["project_collection_path"] = path
tmp = f"{record}.tmp.{os.getpid()}"
with open(tmp, "w") as handle:
    json.dump(data, handle)
os.replace(tmp, record)
PY
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
  if [[ "${PROJECT_BUILD_RC}" == "0" && "${CUSTOM_BUILD_RC:-0}" == "0" && "${GLOBAL_BUILD_RC:-0}" == "0" ]]; then
    _record_if_built
    echo '{"status":"rebuilt"}'
    exit 0
  fi
  printf '[reindex-memories] ensure finished %s\n' "$(_engine_rc_suffix)" \
    >> "${LOG_FILE}" 2>/dev/null || true
  _stale "rebuild-failed"
}

if [[ "${MODE}" == "sync" ]]; then
  _any_collection_exists || { echo '{"status":"no-vault"}'; exit 0; }
  _acquire_build_lock || _stale "build-lock-timeout"
  _foreground_build
fi

if [[ "${MODE}" == "ensure" ]]; then
  # Fail-open: without any configured corpus there is nothing to index/record.
  _any_collection_exists || { echo '{"status":"no-vault"}'; exit 0; }

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
  bg_message="mdctx build (configured collections) launched in background"
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
