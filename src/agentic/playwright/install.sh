#!/usr/bin/env bash
# =============================================================================
# src/agentic/playwright/install.sh
# Installs @playwright/mcp globally at the pinned version (T1.2).
#
# The docker launch path (mcp/playwright image) is preferred; the npm binary is
# the fallback used when no docker daemon is available. The mcp.json command
# resolves it by explicit prefix — install it here or non-docker machines fail
# at launch.
#
# Idempotent: skips when the pinned version is already installed.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

PLAYWRIGHT_MCP_VERSION=""
# shellcheck source=./versions.env
source "${MODULE_DIR}/versions.env"

# Prints the installed global binary path, trying the npm prefix candidates the
# mcp.json launcher uses. Never PATH-resolves.
_installed_bin() {
  local prefix cand
  prefix="$(npm config get prefix 2>/dev/null || true)"
  for cand in ${prefix:+"${prefix}/bin/"} "${HOME}/.npm-global/bin/" "/usr/local/bin/"; do
    [[ -n "${cand}" && -x "${cand}playwright-mcp" ]] && { printf '%s' "${cand}playwright-mcp"; return 0; }
  done
  return 1
}

main() {
  _info "playwright — install"

  if ! command -v node >/dev/null 2>&1; then
    _fatal "node is required but not installed."
    exit 1
  fi
  _skip "node ($(node --version)) found"

  if ! command -v npm >/dev/null 2>&1; then
    _fatal "npm is required but not installed."
    exit 1
  fi
  _skip "npm ($(npm --version)) found"

  local bin installed_version
  bin="$(_installed_bin || true)"
  if [[ -n "${bin}" ]]; then
    installed_version="$("${bin}" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
    if [[ "${installed_version}" == "${PLAYWRIGHT_MCP_VERSION}" ]]; then
      _skip "playwright-mcp ${installed_version} already installed (pinned)"
      return 0
    fi
    _info "playwright-mcp ${installed_version:-unknown} installed, pin is ${PLAYWRIGHT_MCP_VERSION} — reinstalling"
  fi

  if npm install -g "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}" >/dev/null 2>&1; then
    _ok "playwright-mcp@${PLAYWRIGHT_MCP_VERSION} installed"
  else
    _warn "npm install -g @playwright/mcp@${PLAYWRIGHT_MCP_VERSION} failed — check network / npm registry access."
    return 1
  fi
}

main "$@"
