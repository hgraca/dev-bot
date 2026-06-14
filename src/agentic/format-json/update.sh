#!/usr/bin/env bash
# Update format-json — upgrades prettier to the latest version via npm.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

main() {
  _info "format-json"

  if ! command -v python3 &>/dev/null; then
    echo "  Error: python3 not found — re-run bin/install.sh." >&2
    exit 1
  fi

  if ! command -v node &>/dev/null; then
    echo "  Error: node not found — re-run bin/install.sh." >&2
    exit 1
  fi

  if ! command -v prettier &>/dev/null; then
    echo "  Error: prettier not found — re-run bin/install.sh." >&2
    exit 1
  fi

  _info "Updating prettier via npm..."
  npm update -g prettier
  _ok "prettier ($(prettier --version 2>&1))"
}

main
