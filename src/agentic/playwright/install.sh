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
    else
      _info "playwright-mcp ${installed_version:-unknown} installed, pin is ${PLAYWRIGHT_MCP_VERSION} — reinstalling"
      bin=""
    fi
  fi

  if [[ -z "${bin}" ]]; then
    if npm install -g "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}" >/dev/null 2>&1; then
      _ok "playwright-mcp@${PLAYWRIGHT_MCP_VERSION} installed"
      bin="$(_installed_bin || true)"
    else
      _warn "npm install -g @playwright/mcp@${PLAYWRIGHT_MCP_VERSION} failed — check network / npm registry access."
      return 1
    fi
  fi

  # Run even when the package is already at the pin: the browser can be absent
  # while the npm binary is current (that is exactly how the docker-absent
  # fallback broke — it launched with no chromium to drive).
  _ensure_browser "${bin}"
}

# The npm binary is the docker-absent fallback in mcp.json, which launches it
# with `--browser chromium`; the docker path brings its own mcp/playwright image,
# so the local browser only matters when no daemon is reachable. install-browser
# is idempotent: it is a quick cache check once the build is present.
# The shared browser libs (`npx playwright install-deps chromium`) remain a host
# prerequisite the module cannot apt-get for.
_ensure_browser() {
  local bin="$1"
  [[ -n "${bin}" ]] || return 0
  if docker info >/dev/null 2>&1; then
    _skip "docker daemon present — browser comes from the mcp/playwright image"
    return 0
  fi
  if "${bin}" install-browser chrome-for-testing >/dev/null 2>&1; then
    _ok "chromium (chrome-for-testing) ready for the docker-absent fallback"
  else
    _warn "could not install the chromium browser — the docker-absent fallback will fail to launch. Run: '${bin}' install-browser chrome-for-testing"
  fi
}

main "$@"
