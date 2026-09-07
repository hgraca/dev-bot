#!/usr/bin/env bash
# =============================================================================
# src/agentic/mdctx/install.sh
# Installs the mdctx CLI + MCP server (global npm package `mdctx`).
# - Skips when the mdctx binary is already on PATH (idempotent, fast repeat runs)
# - No models to pull, no GPU, no docker — mdctx is zero-ML-dependency
#
# MCP registration is handled by init (mcp.opencode.json / mcp.claudecode.json);
# no per-project config is written here.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# ── main ─────────────────────────────────────────────────────────────────────

main() {
  _info "mdctx — install"

  if command -v mdctx >/dev/null 2>&1; then
    _skip "mdctx already installed: $(mdctx --version 2>/dev/null || echo 'present')"
    _ok "mdctx installation complete"
    return 0
  fi

  if ! command -v npm >/dev/null 2>&1; then
    _error "npm not found — cannot install mdctx. Install Node.js >= 18 first."
    return 1
  fi

  _info "Installing mdctx via npm (global)..."
  if npm install -g mdctx >/dev/null 2>&1; then
    _ok "mdctx installed: $(mdctx --version 2>/dev/null || echo 'present')"
  else
    _error "npm install -g mdctx failed — check network / npm registry access."
    return 1
  fi

  _ok "mdctx installation complete"
}

main
