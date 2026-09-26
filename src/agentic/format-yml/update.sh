#!/usr/bin/env bash
# Update format-yml — upgrades prettier to the latest version via npm.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/functions.sh"

main() {
  _info "format-yml"

  if ! command -v python3 >/dev/null 2>&1; then
    _fatal "python3 not found — re-run bin/install.sh."
    exit 1
  fi

  if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    _fatal "node and npm are required — re-run bin/install.sh."
    exit 1
  fi

  if ! command -v prettier >/dev/null 2>&1; then
    _info "Installing prettier globally via npm..."
    npm install -g prettier
  else
    _info "Updating prettier via npm..."
    npm update -g prettier
  fi

  # Verify rather than assume: under `set -e` a failing command substitution does
  # not abort, so `prettier --version` inside _ok would report success for a
  # prettier that is not runnable.
  if ! command -v prettier >/dev/null 2>&1; then
    _fatal "prettier is still not on PATH after npm — check the npm global prefix."
    exit 1
  fi

  _ok "prettier ($(prettier --version 2>&1))"
}

main
