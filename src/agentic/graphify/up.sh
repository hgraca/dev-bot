#!/usr/bin/env bash
# =============================================================================
# src/agentic/graphify/up.sh
# Prunes stale entries from graphify-out/cache so the AST cache does not grow
# without bound. Runs on `devbot up` — the project directory is passed as $1 by
# bin/up.sh; falls back to cwd. Non-fatal: housekeeping must never block the boot.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# Retention window for graphify-out/cache entries, in days. A cache file not
# modified within this many days is removed. Override via the environment.
CACHE_MAX_AGE_DAYS="${GRAPHIFY_CACHE_MAX_AGE_DAYS:-7}"

# The project directory is passed as $1 by bin/up.sh; fall back to cwd.
PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd 2>/dev/null || true)"

# Detached so a scan over a large cache never delays `devbot up`. Pruning by
# mtime is safe: a deleted entry costs a recompute at worst, never a failure.
_prune_cache_in_background() {
  [[ -n "${PROJECT_DIR}" ]] || return 0

  local cache_dir="${PROJECT_DIR}/graphify-out/cache"
  [[ -d "${cache_dir}" ]] || return 0

  ( nohup find "${cache_dir}" -type f -mtime "+${CACHE_MAX_AGE_DAYS}" -delete >/dev/null 2>&1 & )
  _ok "graphify cache: pruning entries older than ${CACHE_MAX_AGE_DAYS}d in background"
}

main() {
  _info "graphify — up"
  _prune_cache_in_background
  _ok "graphify up complete"
}

main "$@"
