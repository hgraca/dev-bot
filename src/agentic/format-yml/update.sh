#!/usr/bin/env bash
# Update format-yml — upgrades prettier to the latest version via npm.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

main() {
  _info "format-yml"

  if ! command -v python3 >/dev/null 2>&1; then
    _fatal "python3 not found — re-run bin/install.sh."
    exit 1
  fi

  if ! command -v node >/dev/null 2>&1; then
    _fatal "node not found — re-run bin/install.sh."
    exit 1
  fi

  if ! command -v prettier >/dev/null 2>&1; then
    _fatal "prettier not found — re-run bin/install.sh."
    exit 1
  fi

  _info "Updating prettier via npm..."
  npm update -g prettier
  _ok "prettier ($(prettier --version 2>&1))"
}

main
