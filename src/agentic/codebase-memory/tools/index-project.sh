#!/usr/bin/env bash
# =============================================================================
# src/agentic/codebase-memory/tools/index-project.sh
# Background index of the project for the codebase-memory engine.
#
# The codebase-memory engine indexes nothing until an explicit index_repository,
# and its broadness heuristic rejects container mount roots (/app, /workspace)
# as "too broad to index as one root" (audit-52/54/55/56 NOTE). Per the
# operator decision, dev-bot primes the engine — from `devbot up` and from an
# agent-run commit — against the project's `src` or `app` folder (whichever
# exists at the project root), so structural search works out of the box and
# never hits the too-broad guard.
#
# The index goes through the shared gateway over MCP, NOT a host binary: the
# store lives on a Docker named volume, which only the gateway can write (see
# the module's docker-compose.yml STORE note). mcp-index.py speaks the
# streamable-http conversation.
#
# Invoked by the module's up.sh (before the harness starts) and by its
# command.after `git commit` hook. Fail-open and silent like the graphify
# background updater: no codebase-memory provider, no gateway, or no src/app dir
# means "nothing to do here" — exit 0 quietly.
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

# ── Gateway-facing path ────────────────────────────────────────────────────────
# The gateway resolves paths in ITS mount namespace. In a container whose project
# is bind-mounted from a different host path (the e2e fixture mounts a host run
# dir at /app), the local path is invisible to it even when the gateway can reach
# the project. CODEBASE_MEMORY_HOST_PROJECT names the host path of this same
# project, so the gateway is handed that — the same src|app subdir, under the
# host root.
GATEWAY_INDEX_ROOT="${INDEX_ROOT}"
if [[ -n "${CODEBASE_MEMORY_HOST_PROJECT:-}" ]]; then
  GATEWAY_INDEX_ROOT="${CODEBASE_MEMORY_HOST_PROJECT%/}${INDEX_ROOT#"${PROJECT_PATH}"}"
fi

# ── Log target + mutex ─────────────────────────────────────────────────────────
LOG_DIR="${PROJECT_PATH}/.agents/logs"
mkdir -p "${LOG_DIR}" 2>/dev/null || exit 0
LOG_FILE="${LOG_DIR}/codebase-memory-index.log"
LOCK_FILE="${LOG_DIR}/codebase-memory-index.lock"

# ── Gateway mount scope ────────────────────────────────────────────────────────
# The shared gateway bind-mounts its repo root at the same absolute path (see the
# module's docker-compose.yml), so a project outside that root is invisible to it.
# index_repository then fails with a generic "check repo_path" hint and the hook
# logs rc=1 on every session — an environment condition, not a wiring failure
# (audit-65/66). Read the running container's real bind source (as up.sh does):
# this process's own env can diverge from the env the gateway was created with.
# Fall back to the configured default only when docker/daemon/container is absent.
GATEWAY_ROOT=""
if command -v docker >/dev/null 2>&1; then
  GATEWAY_ROOT="$(docker inspect \
    --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{"\n"}}{{end}}{{end}}' \
    dev-bot-codebase-memory-mcp 2>/dev/null | head -1)"
fi
[[ -n "${GATEWAY_ROOT}" ]] || GATEWAY_ROOT="${CODEBASE_MEMORY_ROOT:-${HOME}}"
GATEWAY_ROOT="${GATEWAY_ROOT%/}"
if [[ "${GATEWAY_INDEX_ROOT}" != "${GATEWAY_ROOT}" && "${GATEWAY_INDEX_ROOT}" != "${GATEWAY_ROOT}/"* ]]; then
  {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] WARN: index-project skipped ${GATEWAY_INDEX_ROOT} — outside the codebase-memory gateway's repo root (${GATEWAY_ROOT}); set CODEBASE_MEMORY_ROOT to cover it and run 'devbot up'"
  } >> "${LOG_FILE}" 2>&1
  exit 0
fi

exec 200>"${LOCK_FILE}" 2>/dev/null || exit 0
# audit-25 F2: flock(1) is util-linux (Linux-only) — macOS lacks it. Fall back
# to python fcntl on the inherited fd 200.
{ flock -n 200 2>/dev/null || python3 -c 'import fcntl; fcntl.flock(200, fcntl.LOCK_EX|fcntl.LOCK_NB)' 2>/dev/null; } || exit 0

# ── Launch the one-shot index in the background ───────────────────────────────
# Re-indexing an already-indexed project is incremental.
(
  {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] index-project start root=${GATEWAY_INDEX_ROOT}"
    python3 "${SCRIPT_DIR}/mcp-index.py" "${CBM_URL}" "${GATEWAY_INDEX_ROOT}"
    # Capture before the $(date) substitution below: expanding a command
    # substitution resets $?, so `rc=$?` inline would always report date's 0.
    rc=$?
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] index-project finished rc=${rc}"
  } >> "${LOG_FILE}" 2>&1
) &
disown 2>/dev/null || true

exit 0
