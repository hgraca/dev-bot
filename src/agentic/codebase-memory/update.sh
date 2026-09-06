#!/usr/bin/env bash
# =============================================================================
# src/agentic/codebase-memory/update.sh
# Updates the codebase-memory-mcp native binary to the latest npm version.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

main() {
  _info "codebase-memory — update"

  if ! command -v npm >/dev/null 2>&1; then
    _error "npm not found — cannot update codebase-memory-mcp. Install Node.js >= 18 first."
    return 1
  fi

  # Self-healing: `npm update -g` on a never-installed package is a silent
  # no-op (exit 0, nothing installed). devbot update never runs module
  # install.sh, so an install that adopts codebase-memory via update+reinit
  # would register the MCP server with no binary. Fall back to install when
  # the binary is missing (chrome-devtools update pattern).
  if command -v codebase-memory-mcp >/dev/null 2>&1; then
    _info "Updating codebase-memory-mcp via npm (global)..."
    if npm update -g codebase-memory-mcp >/dev/null 2>&1; then
      _ok "codebase-memory-mcp updated: $(codebase-memory-mcp --version 2>/dev/null || echo 'present')"
    else
      _error "npm update -g codebase-memory-mcp failed — check network / npm registry access."
      return 1
    fi
  else
    _warn "codebase-memory-mcp not installed — installing instead of updating"
    if npm install -g codebase-memory-mcp >/dev/null 2>&1; then
      _ok "codebase-memory-mcp installed: $(codebase-memory-mcp --version 2>/dev/null || echo 'present')"
    else
      _error "npm install -g codebase-memory-mcp failed — check network / npm registry access."
      return 1
    fi
  fi

  _ok "codebase-memory update complete"
}

main
