#!/usr/bin/env bash
# =============================================================================
# src/agentic/mdctx/pre.sh
# Prerequisites check for the mdctx module.
# Verifies Node.js >= 18 and npm are available (npm engines field requires
# node >= 18; the binary is installed globally via npm).
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
  _info "mdctx — prerequisites"

  # Node.js >= 18 (npm package engines field requires node >= 18)
  if command -v node >/dev/null 2>&1; then
    local node_ver major
    node_ver="$(node --version | sed 's/^v//')"
    major="${node_ver%%.*}"
    _ok "Node.js found: v${node_ver}"
    if [[ "${major}" -lt 18 ]]; then
      _fatal "Node.js >= 18 is required (found v${node_ver}) — mdctx requires node >= 18: https://nodejs.org/"
      exit 1
    fi
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

  _ok "mdctx prerequisites check complete"
}

main "$@"
