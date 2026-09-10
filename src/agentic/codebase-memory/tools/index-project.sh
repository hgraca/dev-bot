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
# Invoked by the module's session.created hook (both harnesses). Fail-open and
# silent like the graphify background updater: no codebase-memory provider, no
# engine binary, or no src/app dir means "nothing to do here" — exit 0 quietly.
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
command -v codebase-memory-mcp >/dev/null 2>&1 || exit 0

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
# `codebase-memory-mcp cli index_repository` runs a temporary supervised worker
# (CLI mode — no daemon). Re-indexing an already-indexed project is incremental
# (the watcher keeps it fresh afterwards).
(
  {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] index-project start root=${INDEX_ROOT}"
    codebase-memory-mcp cli index_repository --repo-path "${INDEX_ROOT}"
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] index-project finished rc=$?"
  } >> "${LOG_FILE}" 2>&1
) &
disown 2>/dev/null || true

exit 0
