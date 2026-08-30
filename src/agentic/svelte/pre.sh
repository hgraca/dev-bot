#!/usr/bin/env bash
# =============================================================================
# src/agentic/svelte/pre.sh
# Prerequisites check for the svelte module.
# Verifies Node.js >= 18 and npm are available (required for MCP server,
# OpenCode plugin, and project scaffolding).
#
# Run by bin/install.sh and bin/update.sh — looped over all agentic modules.
# Idempotent — safe to re-run at any time.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

main() {
  _info "svelte — prerequisites"

  # Node.js >= 18
  if command -v node >/dev/null 2>&1; then
    _ok "Node.js found: $(node --version)"
  else
    _fatal "Node.js not found. Install Node.js >= 18: https://nodejs.org/"
    exit 1
  fi

  # npm
  if command -v npm >/dev/null 2>&1; then
    _ok "npm found: $(npm --version)"
  else
    _fatal "npm not found. npm ships with Node.js."
    exit 1
  fi

  _ok "svelte prerequisites check complete"
}

main "$@"
