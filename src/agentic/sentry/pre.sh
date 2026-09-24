#!/usr/bin/env bash
# src/agentic/sentry/pre.sh
# Prerequisites check for the Sentry module.
# Run automatically by bin/install.sh and bin/update.sh.
#
# There is no local service and no binary to fetch: the MCP server is hosted at
# https://mcp.sentry.dev/mcp, so the only hard prerequisite is npx (for the
# agent skills). curl is optional — it only powers the reachability hint.
#
# Non-destructive — warnings only for missing optional tools.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

_main() {
  local all_ok=true

  _header_3 "Sentry prerequisites"

  # npx / node (required for installing agent skills)
  if command -v npx >/dev/null 2>&1; then
    _ok "npx (for installing agent skills)"
  else
    _warn "npx not found (node/npm required) — cannot install Sentry agent skills"
    all_ok=false
  fi

  # curl (optional — only used for the reachability hint)
  if command -v curl >/dev/null 2>&1; then
    _ok "curl (for the endpoint reachability hint)"
  else
    _info "curl not found — endpoint reachability hint will be skipped"
  fi

  # The token is resolved by the client at launch, never stored in a config.
  if [[ -n "${SENTRY_ACCESS_TOKEN:-}" ]]; then
    _ok "SENTRY_ACCESS_TOKEN is set"
  else
    _warn "SENTRY_ACCESS_TOKEN is unset — the sentry MCP server will start but every call will fail"
  fi

  if [[ "${all_ok}" == "false" ]]; then
    _warn "One or more prerequisites missing — install/update may be partial."
  fi
}

_main
