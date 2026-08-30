#!/usr/bin/env bash
# Update git-report — verifies python3 and git are still available.
# No updatable OS-level packages — git-report uses Python stdlib only.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

main() {
  _info "git-report"

  if ! command -v python3 >/dev/null 2>&1; then
    _fatal "python3 not found — re-run bin/install.sh."
    exit 1
  fi

  if ! command -v git >/dev/null 2>&1; then
    _fatal "git not found — re-run bin/install.sh."
    exit 1
  fi

  _skip "git-report — no OS dependencies to update"
}

main
