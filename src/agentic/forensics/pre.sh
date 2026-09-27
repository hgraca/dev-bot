#!/usr/bin/env bash
# =============================================================================
# src/agentic/forensics/pre.sh
# Prerequisites check for the forensics module.
#
# Run by bin/install.sh and bin/update.sh — looped over all agentic modules.
# Idempotent — safe to re-run at any time.
#
# python3 and git are hard requirements: the core, the history miner and the
# sqlite store are Python, and the whole method mines git history. docker is a
# warning-only runtime — language engines run in a container when the project
# has no local engine.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/functions.sh"

main() {
  _info "forensics — prerequisites"

  if command -v python3 >/dev/null 2>&1; then
    _ok "python3 found: $(python3 --version 2>&1)"
  else
    _fatal "python3 not found — the forensics core requires it: https://www.python.org/"
    exit 1
  fi

  if command -v git >/dev/null 2>&1; then
    _ok "git found: $(git --version)"
  else
    _fatal "git not found — forensics mines git history"
    exit 1
  fi

  if command -v docker >/dev/null 2>&1; then
    _ok "docker found"
  else
    _warn "docker not found — language engines run in containers when no local engine exists"
  fi

  _ok "forensics prerequisites check complete"
}

main "$@"
