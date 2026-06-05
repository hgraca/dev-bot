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

  if ! command -v python3 &>/dev/null; then
    echo "  Error: python3 not found — re-run bin/install.sh." >&2
    exit 1
  fi

  if ! command -v git &>/dev/null; then
    echo "  Error: git not found — re-run bin/install.sh." >&2
    exit 1
  fi

  _skip "git-report — no OS dependencies to update"
}

main
