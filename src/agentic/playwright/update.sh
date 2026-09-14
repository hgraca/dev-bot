#!/usr/bin/env bash
# =============================================================================
# src/agentic/playwright/update.sh
# Updates playwright: bumps the npm fallback binary to npm latest and rewrites
# the pin (T1.2 policy: versions change ONLY on `devbot update`).
#
# versions.env is rewritten in place so every consumer installs the same new
# pin on their next install.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

main() {
  _info "playwright — update"

  if ! command -v npm >/dev/null 2>&1; then
    _error "npm not found — cannot update @playwright/mcp. Install Node.js >= 18 first."
    return 1
  fi

  if LATEST="$(npm view "@playwright/mcp" version 2>/dev/null)" && [[ -n "${LATEST}" ]]; then
    if npm install -g "@playwright/mcp@${LATEST}" >/dev/null 2>&1; then
      _ok "playwright-mcp updated: ${LATEST}"
    else
      _error "npm install -g @playwright/mcp@${LATEST} failed — check network / npm registry access."
      return 1
    fi
    # sed->tmp->mv (no bare `sed -i` — macOS requires a backup suffix).
    sed "s/^PLAYWRIGHT_MCP_VERSION=.*/PLAYWRIGHT_MCP_VERSION=${LATEST}/" \
      "${MODULE_DIR}/versions.env" > "${MODULE_DIR}/versions.env.tmp" \
      && mv "${MODULE_DIR}/versions.env.tmp" "${MODULE_DIR}/versions.env"
    _ok "pin bumped to ${LATEST} (versions.env)"
  else
    _warn "npm view failed (offline?) — keeping existing install and pin"
  fi

  _ok "playwright update complete"
}

main "$@"
