#!/usr/bin/env bash
# =============================================================================
# src/agentic/mdctx/update.sh
# Updates the mdctx CLI + MCP server to the latest npm version.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

main() {
  _info "mdctx — update"

  if ! command -v npm >/dev/null 2>&1; then
    _error "npm not found — cannot update mdctx. Install Node.js >= 18 first."
    return 1
  fi

  # Self-healing: `npm update -g` on a never-installed package is a silent
  # no-op (exit 0, nothing installed). devbot update never runs module
  # install.sh, so an install that adopts mdctx via update+reinit (memory_search
  # _provider absent => mdctx default) would register the MCP server with no
  # binary. Fall back to install when the binary is missing (codebase-memory /
  # chrome-devtools update pattern).
  if command -v mdctx >/dev/null 2>&1; then
    _info "Updating mdctx via npm (global)..."
    if npm update -g mdctx >/dev/null 2>&1; then
      _ok "mdctx updated: $(mdctx --version 2>/dev/null || echo 'present')"
    else
      _error "npm update -g mdctx failed — check network / npm registry access."
      return 1
    fi
  else
    _warn "mdctx not installed — installing instead of updating"
    if npm install -g mdctx >/dev/null 2>&1; then
      _ok "mdctx installed: $(mdctx --version 2>/dev/null || echo 'present')"
    else
      _error "npm install -g mdctx failed — check network / npm registry access."
      return 1
    fi
  fi

  _ok "mdctx update complete"
}

main
