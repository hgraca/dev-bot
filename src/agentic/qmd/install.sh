#!/usr/bin/env bash
# Install QMD (Quick Markdown search) CLI via npm.
# Installs the @tobilu/qmd npm package globally.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.
# GATE: Requires npm (Node.js package manager).

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

main() {
  _info "qmd"

  # ── Dependency check: npm ────────────────────────────────────────────────
  if ! command -v npm &>/dev/null; then
    _error "npm is required but not installed."
    echo "  Install Node.js via your system package manager (apt, dnf, brew) or nvm." >&2
    exit 1
  fi

  # ── Install/verify QMD ───────────────────────────────────────────────────
  if ! command -v qmd &>/dev/null; then
    _info "Installing @tobilu/qmd via npm..."
    npm install -g @tobilu/qmd 2>&1 | sed 's/^/  /'
    _ok "QMD installed: $(qmd --version 2>/dev/null || true)"
  else
    _skip "QMD ($(qmd --version 2>/dev/null || echo 'installed'))"
  fi
}

main
