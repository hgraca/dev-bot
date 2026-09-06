#!/usr/bin/env bash
# =============================================================================
# src/agentic/codebase-memory/install.sh
# Installs the codebase-memory-mcp native binary (global npm package).
# - Skips when the binary is already on PATH (idempotent, fast repeat runs)
# - The npm package's bin.js installs/verifies the native runtime on first use
#
# MCP registration is handled by init (mcp.opencode.json / mcp.claudecode.json);
# no per-project config is written — codebase-memory-mcp stores its settings
# account-wide via `codebase-memory-mcp config set`, not per-project files.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# ── main ─────────────────────────────────────────────────────────────────────

main() {
  _info "codebase-memory — install"

  if command -v codebase-memory-mcp >/dev/null 2>&1; then
    _skip "codebase-memory-mcp already installed: $(codebase-memory-mcp --version 2>/dev/null || echo 'present')"
    _ok "codebase-memory installation complete"
    return 0
  fi

  if ! command -v npm >/dev/null 2>&1; then
    _error "npm not found — cannot install codebase-memory-mcp. Install Node.js >= 18 first."
    return 1
  fi

  _info "Installing codebase-memory-mcp via npm (global)..."
  if npm install -g codebase-memory-mcp >/dev/null 2>&1; then
    _ok "codebase-memory-mcp installed: $(codebase-memory-mcp --version 2>/dev/null || echo 'present')"
  else
    _error "npm install -g codebase-memory-mcp failed — check network / npm registry access."
    return 1
  fi

  _ok "codebase-memory installation complete"
}

main
