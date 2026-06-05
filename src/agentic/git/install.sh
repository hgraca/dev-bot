#!/usr/bin/env bash
# Install git-report dependencies — ensures python3 and git are available.
# git-report is a Python script with no third-party dependencies (stdlib only).
# Idempotent — verifies python3 and git exist.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

main() {
  _info "git-report"

  if ! command -v python3 &>/dev/null; then
    echo "  Error: python3 is required but not installed." >&2
    echo "  Install via your system package manager (apt, dnf, brew)." >&2
    exit 1
  fi

  if ! command -v git &>/dev/null; then
    echo "  Error: git is required but not installed." >&2
    echo "  Install via your system package manager (apt, dnf, brew, xcode-select)." >&2
    exit 1
  fi

  _skip "git-report — uses stdlib only, no dependencies to install"
}

main
