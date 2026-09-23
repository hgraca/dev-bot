#!/usr/bin/env bash
# =============================================================================
# src/agentic/refactor/pre.sh
# Prerequisites check for the refactor module.
#
# Run by bin/install.sh and bin/update.sh — looped over all agentic modules.
# Idempotent — safe to re-run at any time.
#
# Hard requirements are limited to what the shared lifecycle helpers need; the
# tool's own runtime needs (docker for the PHP container, bun for the TS core)
# are warnings so a missing runtime never blocks a dev-bot install.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/functions.sh"

main() {
  _info "refactor — prerequisites"

  # Required: python3 backs the shared lifecycle helpers (read_jsonc.py, etc.).
  if command -v python3 >/dev/null 2>&1; then
    _ok "python3 found: $(python3 --version 2>&1)"
  else
    _fatal "python3 not found — devbot's lifecycle helpers require it: https://www.python.org/"
    exit 1
  fi

  # Runtime (warn only — never block install): docker runs Rector in a PHP
  # container with the project mounted.
  if command -v docker >/dev/null 2>&1; then
    _ok "docker found"
  else
    _warn "docker not found — the refactor tool's PHP container runner needs it at runtime"
  fi

  # Runtime (warn only): bun runs the tool's TS core (provided by tools-mcp).
  if command -v bun >/dev/null 2>&1; then
    _ok "bun found: $(bun --version 2>/dev/null || echo installed)"
  else
    _warn "bun not found — the tools-mcp module installs it; the refactor tool needs it to run"
  fi

  _ok "refactor prerequisites check complete"
}

main "$@"
