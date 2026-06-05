#!/usr/bin/env bash
# Install format-md dependencies — checks for node, installs prettier globally via npm.
# Idempotent — skips if prettier is already installed.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

main() {
  _info "format-md"

  if ! command -v python3 &>/dev/null; then
    echo "  Error: python3 is required but not installed." >&2
    echo "  Install via your system package manager (apt, dnf, brew)." >&2
    exit 1
  fi
  _skip "python3 found"

  if ! command -v node &>/dev/null; then
    echo "  Error: node is required but not installed." >&2
    echo "  Install via your system package manager:" >&2
    echo "    Ubuntu/Debian: apt install nodejs npm" >&2
    echo "    Fedora:        dnf install nodejs npm" >&2
    echo "    macOS:         brew install node" >&2
    exit 1
  fi
  _skip "node ($(node --version)) found"

  if command -v prettier &>/dev/null; then
    _skip "prettier ($(prettier --version 2>&1))"
    exit 0
  fi

  _info "Installing prettier globally via npm..."
  npm install -g prettier
  _ok "prettier installed ($(prettier --version 2>&1))"
}

main
