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

# version from versions.env — T1.2: install installs the exact pin.
CHROME_DEVTOOLS_MCP_VERSION=""
# shellcheck source=./versions.env
source "${MODULE_DIR}/versions.env"

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

# Prints the installed global binary path, trying the npm prefix candidates the
# serve launcher uses. Never PATH-resolves (avoids a stale system binary).
_installed_bin() {
  local prefix cand
  prefix="$(npm config get prefix 2>/dev/null || true)"
  for cand in ${prefix:+"${prefix}/bin/"} "${HOME}/.npm-global/bin/" "/usr/local/bin/"; do
    [[ -n "${cand}" && -x "${cand}chrome-devtools-mcp" ]] && { printf '%s' "${cand}chrome-devtools-mcp"; return 0; }
  done
  return 1
}

_install_server() {
  local bin installed_version
  bin="$(_installed_bin || true)"
  if [[ -n "${bin}" ]]; then
    installed_version="$("${bin}" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
    if [[ "${installed_version}" == "${CHROME_DEVTOOLS_MCP_VERSION}" ]]; then
      _skip "chrome-devtools-mcp ${installed_version} already installed (pinned)"
      return 0
    fi
    _info "chrome-devtools-mcp ${installed_version:-unknown} installed, pin is ${CHROME_DEVTOOLS_MCP_VERSION} — reinstalling"
  fi

  if npm install -g "chrome-devtools-mcp@${CHROME_DEVTOOLS_MCP_VERSION}" >/dev/null 2>&1; then
    _ok "chrome-devtools-mcp@${CHROME_DEVTOOLS_MCP_VERSION} installed"
  else
    _warn "npm install -g chrome-devtools-mcp@${CHROME_DEVTOOLS_MCP_VERSION} failed — check network / npm registry access."
    return 1
  fi
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

  if ! command -v npm >/dev/null 2>&1; then
    _fatal "npm is required but not installed."
    exit 1
  fi
  _skip "npm ($(npm --version)) found"

  # T1.2: the server binary itself. The mcp.json launcher resolves it by
  # explicit prefix — install it here or every MCP call fails at launch.
  _install_server || return 1

  if _chromium_present; then
    _skip "playwright chromium already present"
    return 0
  fi

  _info "Installing Playwright Chromium (chrome-devtools needs a sandboxable browser)..."
  # Force a FIXED browsers path on every platform (audit-01 macOS FAIL):
  # Playwright's default cache is ~/Library/Caches/ms-playwright on macOS but
  # ~/.cache/ms-playwright on Linux — the MCP launch wrapper globs the Linux
  # path. Pinning PLAYWRIGHT_BROWSERS_PATH keeps the glob valid everywhere.
  if PLAYWRIGHT_BROWSERS_PATH="$HOME/.cache/ms-playwright" npx -y playwright install chromium; then
    _ok "Playwright Chromium installed"
  else
    _warn "playwright install chromium failed — chrome-devtools will require a system Chrome"
  fi
}

main "$@"
