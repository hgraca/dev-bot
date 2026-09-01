#!/usr/bin/env bash
# =============================================================================
# src/agentic/chrome-devtools/install.sh
# Installs chrome-devtools dependencies — provisions a sandboxable Chromium
# via Playwright so the MCP wrapper can always launch a browser.
#
# The chrome-devtools MCP server needs a Chromium binary to drive. The launch
# wrapper only discovers Playwright-downloaded Chromium (never assumes system
# Chrome), so setup must actually download it — otherwise every real call
# fails with "Could not find Google Chrome executable" (audit-25 F4).
#
# Idempotent: skips the download when a Chromium binary already exists in
# ~/.cache/ms-playwright.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

_chromium_present() {
  # True if ANY Playwright-downloaded Chromium exists (Linux or macOS layout).
  # Uses a glob-count rather than ls's exit code: ls would report failure when
  # one of the two platform patterns doesn't match, even if the other does.
  local found
  found="$(ls "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux*/chrome \
    "$HOME"/.cache/ms-playwright/chromium-*/chrome-mac/Chromium.app/Contents/MacOS/Chromium \
    2>/dev/null | head -1)"
  [[ -n "${found}" ]]
}

main() {
  _info "chrome-devtools"

  if ! command -v node >/dev/null 2>&1; then
    _fatal "node is required but not installed."
    echo "  Install via your system package manager:" >&2
    echo "    Ubuntu/Debian: apt install nodejs npm" >&2
    echo "    Fedora:        dnf install nodejs npm" >&2
    echo "    macOS:         brew install node" >&2
    exit 1
  fi
  _skip "node ($(node --version)) found"

  if _chromium_present; then
    _skip "playwright chromium already present"
    return 0
  fi

  _info "Installing Playwright Chromium (chrome-devtools needs a sandboxable browser)..."
  if npx -y playwright install chromium; then
    _ok "Playwright Chromium installed"
  else
    _warn "playwright install chromium failed — chrome-devtools will require a system Chrome"
  fi
}

main "$@"
