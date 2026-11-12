#!/usr/bin/env bash
# =============================================================================
# src/agentic/autobot/pre.sh
# Prerequisites check for the autobot module.
#
# Run by bin/install.sh and bin/update.sh — looped over all agentic modules.
# install.sh only registers the system crontab line; the agent runtime and the
# CLIs a tick drives are user-provided, so their absence warns rather than
# failing a machine-wide install.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/functions.sh"

main() {
  _info "autobot — prerequisites"

  local failed=0
  local bin

  for bin in bun crontab; do
    if command -v "$bin" >/dev/null 2>&1; then
      _ok "$bin"
    else
      _error "$bin not found — required to run and schedule autobot"
      failed=1
    fi
  done

  for bin in opencode gh git python3; do
    if command -v "$bin" >/dev/null 2>&1; then
      _ok "$bin"
    else
      _warn "$bin not found — required at runtime by autobot ticks"
    fi
  done

  return "$failed"
}

main "$@"
