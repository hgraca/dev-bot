#!/usr/bin/env bash
# =============================================================================
# src/agentic/codebase-index/up.sh
# Removes stale indexing.lock artifacts, then pulls the nomic-embed-text model
# for codebase indexing.
# Runs on `devbot up` — after docker services (including Ollama) are started.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

OLLAMA_API="${OLLAMA_LOCAL_API:-http://localhost:18434}"
MODEL="nomic-embed-text"

# The project directory is passed as $1 by bin/up.sh; fall back to cwd.
PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd 2>/dev/null || true)"

# Remove stale indexing.lock file or directory (see the EISDIR-on-indexing.lock
# incident: a race can corrupt it into a directory that blocks re-indexing).
_remove_stale_indexing_locks() {
  [[ -n "${PROJECT_DIR}" ]] || return 0

  local lock
  for lock in \
    "${PROJECT_DIR}/.opencode/index/indexing.lock" \
    "${PROJECT_DIR}/.claude/index/indexing.lock"; do
    if [[ -e "${lock}" || -L "${lock}" ]]; then
      rm -rf "${lock}"
      _ok "Removed stale lock '${lock}'"
    fi
  done
}

main() {
  _remove_stale_indexing_locks

  _info "codebase-index — up"

  if ! command -v curl &>/dev/null; then
    _skip "curl not available — skipping model pull"
    return 0
  fi

  # Wait for Ollama to be reachable (retry for up to 30s)
  local retries=0
  while ! curl -sf "${OLLAMA_API}/v1/models" &>/dev/null; do
    retries=$((retries + 1))
    if [[ ${retries} -ge 30 ]]; then
      _skip "Ollama not reachable at ${OLLAMA_API} after 30s — skipping model pull"
      return 0
    fi
    sleep 1
  done
  _ok "Ollama reachable at ${OLLAMA_API}"

  # Pull model if not present
  if curl -sf "${OLLAMA_API}/api/tags" | grep -qiF "\"${MODEL}" 2>/dev/null; then
    _skip "Model '${MODEL}' already present"
  else
    _info "Pulling model '${MODEL}'..."
    curl -sf -X POST "${OLLAMA_API}/api/pull" \
      -d "{\"name\": \"${MODEL}\"}" >/dev/null || true
    _ok "Model '${MODEL}' pulled"
  fi

  _ok "codebase-index up complete"
}

main "$@"
