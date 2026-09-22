#!/usr/bin/env bash
# =============================================================================
# src/agentic/codebase-memory/tools/index-project.sh
# Session-start background index of the project for the codebase-memory engine.
#
# The codebase-memory engine indexes nothing until an explicit index_repository,
# and its broadness heuristic rejects container mount roots (/app, /workspace)
# as "too broad to index as one root" (audit-52/54/55/56 NOTE). Per the
# operator decision, dev-bot primes the engine at session start against the
# project's `src` or `app` folder — whichever exists at the project root — so
# structural search works out of the box and never hits the too-broad guard.
#
# The index goes through the shared gateway over MCP, NOT a host binary: the
# store lives on a Docker named volume, which only the gateway can write (see
# the module's docker-compose.yml STORE note). mcp-index.py speaks the
# streamable-http conversation.
#
# Invoked by the module's session.created hook (both harnesses). Fail-open and
# silent like the graphify background updater: no codebase-memory provider, no
# gateway, or no src/app dir means "nothing to do here" — exit 0 quietly.
# Runs detached and logs to .agents/logs/codebase-memory-index.log.
#
# Usage: index-project.sh <project-path>
# GATE: Must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -uo pipefail

PROJECT_PATH="${1:-$(pwd)}"
PROJECT_PATH="$(cd "${PROJECT_PATH}" 2>/dev/null && pwd)" || exit 0

# ── Resolve this script's real dir (tools are symlinked into .opencode/tools) ─
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "${SOURCE}" ]]; do
  DIR="$(cd -P "$(dirname "${SOURCE}")" && pwd)"
  SOURCE="$(readlink "${SOURCE}")"
  [[ "${SOURCE}" != /* ]] && SOURCE="${DIR}/${SOURCE}"
done
SCRIPT_DIR="$(cd -P "$(dirname "${SOURCE}")" && pwd)"

# shellcheck source=../functions.sh
source "${SCRIPT_DIR}/../functions.sh"

# ── Guards (fail-open) ─────────────────────────────────────────────────────────
# Only when codebase-memory is the active codebase engine.
if [[ "$(_devbot_get_codebase_provider "${PROJECT_PATH}")" != "codebase-memory" ]]; then
  exit 0
fi
command -v python3 >/dev/null 2>&1 || exit 0

# The shared gateway must already be up — a bare harness boot without
# `devbot up` has nothing to index into. /dev/tcp is a bash builtin, so this
# probe needs nothing on PATH.
CBM_URL="${CODEBASE_MEMORY_MCP_URL:-http://127.0.0.1:18504/mcp}"
_hostport="${CBM_URL#*://}"
_hostport="${_hostport%%/*}"
CBM_HOST="${_hostport%%:*}"
CBM_PORT="${_hostport##*:}"
[[ "${CBM_PORT}" =~ ^[0-9]+$ ]] || CBM_PORT=18504
(exec 3<>"/dev/tcp/${CBM_HOST}/${CBM_PORT}") 2>/dev/null || exit 0

# Index only `src` or `app`, whichever exists at the project root — the engine
# rejects whole mount roots, and these are the conventional source dirs.
INDEX_ROOT=""
for candidate in src app; do
  if [[ -d "${PROJECT_PATH}/${candidate}" ]]; then
    INDEX_ROOT="${PROJECT_PATH}/${candidate}"
    break
  fi
done
[[ -n "${INDEX_ROOT}" ]] || exit 0

# ── Log target + mutex ─────────────────────────────────────────────────────────
LOG_DIR="${PROJECT_PATH}/.agents/logs"
mkdir -p "${LOG_DIR}" 2>/dev/null || exit 0
LOG_FILE="${LOG_DIR}/codebase-memory-index.log"
LOCK_FILE="${LOG_DIR}/codebase-memory-index.lock"

exec 200>"${LOCK_FILE}" 2>/dev/null || exit 0
# audit-25 F2: flock(1) is util-linux (Linux-only) — macOS lacks it. Fall back
# to python fcntl on the inherited fd 200.
{ flock -n 200 2>/dev/null || python3 -c 'import fcntl; fcntl.flock(200, fcntl.LOCK_EX|fcntl.LOCK_NB)' 2>/dev/null; } || exit 0

# ── Launch the one-shot index in the background ───────────────────────────────
# Re-indexing an already-indexed project is incremental (the gateway's watcher
# keeps it fresh afterwards).
(
  {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] index-project start root=${INDEX_ROOT}"
    python3 "${SCRIPT_DIR}/mcp-index.py" "${CBM_URL}" "${INDEX_ROOT}"
    # Capture before the $(date) substitution below: expanding a command
    # substitution resets $?, so `rc=$?` inline would always report date's 0.
    rc=$?
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] index-project finished rc=${rc}"
  } >> "${LOG_FILE}" 2>&1
) &
disown 2>/dev/null || true

exit 0
