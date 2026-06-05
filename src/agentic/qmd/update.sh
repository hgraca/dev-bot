#!/usr/bin/env bash
# Update QMD (Quick Markdown search) CLI via npm.
# Upgrades @tobilu/qmd to the latest version and refreshes the index.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.
# GATE: Requires npm (Node.js package manager).

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

main() {
  _info "qmd"

  if ! command -v qmd &>/dev/null; then
    _skip "QMD not installed — run bin/install.sh first."
    exit 0
  fi

  local before
  before="$(qmd --version 2>/dev/null || echo 'unknown')"

  _info "Upgrading @tobilu/qmd via npm..."
  if npm install -g @tobilu/qmd 2>&1 | sed 's/^/  /'; then
    local after
    after="$(qmd --version 2>/dev/null || echo 'unknown')"

    if [[ "$before" == "$after" ]]; then
      _ok "QMD already up to date (${before})"
    else
      _ok "QMD upgraded: ${before} → ${after}"
    fi

    # Refresh the local vault index if latent/ exists
    if [[ -d "$(_devbot_get_project_dir "$(pwd)")/memory/latent" ]]; then
      _info "Refreshing QMD index..."
      qmd update 2>/dev/null || true
      qmd embed 2>/dev/null || true
      _ok "QMD index refreshed"
    else
      _skip "No latent/ directory found — skipping index refresh"
    fi
  else
    _error "QMD upgrade failed — try: npm install -g @tobilu/qmd"
    exit 1
  fi
}

main
