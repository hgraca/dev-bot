#!/usr/bin/env bash
# =============================================================================
# src/agentic/repomix/init.sh
# Sets up repomix in a project: copies repomix.config.json and adds it to
# .git/info/exclude so each project has its own copy without committing it.
#
# Usage:
#   init.sh                    # init in current directory
#   init.sh /path/to/project   # init in specified project
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# ── Copy repomix.config.json ────────────────────────────────────────────────
REPOMIX_CONFIG="${PROJECT_DIR}/repomix.config.json"

if [[ -f "${REPOMIX_CONFIG}" ]]; then
  _log "repomix.config.json already exists"
else
  if [[ ! -f "${MODULE_DIR}/repomix.config.dist.json" ]]; then
    _warn "repomix.config.json not found in module — skipping"
  else
    cp "${MODULE_DIR}/repomix.config.dist.json" "${REPOMIX_CONFIG}"
    _log "repomix.config.json copied"
  fi
fi

# ── .git/info/exclude section ───────────────────────────────────────────────
_upsert_gitignore_section "${PROJECT_DIR}/.git/info/exclude" \
  "# >>> DEVBOT - repomix" \
  "# <<< DEVBOT - repomix" \
  "/repomix.config.json"
_log ".git/info/exclude updated with repomix patterns"
