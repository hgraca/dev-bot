#!/usr/bin/env bash
# Install format-json dependencies — checks for node, installs prettier globally via npm.
# Idempotent — skips if prettier is already installed.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

main() {
  _info "format-json"

  if ! command -v python3 >/dev/null 2>&1; then
    _fatal "python3 is required but not installed."
    echo "  Install via your system package manager (apt, dnf, brew)." >&2
    exit 1
  fi
  _skip "python3 found"

  if ! command -v node >/dev/null 2>&1; then
    _fatal "node is required but not installed."
    echo "  Install via your system package manager:" >&2
    echo "    Ubuntu/Debian: apt install nodejs npm" >&2
    echo "    Fedora:        dnf install nodejs npm" >&2
    echo "    macOS:         brew install node" >&2
    exit 1
  fi
  _skip "node ($(node --version)) found"

  if command -v prettier >/dev/null 2>&1; then
    _skip "prettier ($(prettier --version 2>&1))"
  else
    _info "Installing prettier globally via npm..."
    npm install -g prettier
    _ok "prettier installed ($(prettier --version 2>&1))"
  fi
}

main
