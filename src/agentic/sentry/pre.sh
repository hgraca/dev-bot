#!/usr/bin/env bash
# src/agentic/sentry/pre.sh
# Prerequisites check for the Sentry module.
# Run automatically by bin/install.sh and bin/update.sh.
#
# Classification (see the PDR on prerequisite reporting):
#   - npx: manual, fatal — node/npm is not provisioned by this module.
#   - curl: optional — only powers the endpoint reachability hint.
#   - SENTRY_ACCESS_TOKEN: advisory, not a tool — the server starts without it.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

_main() {
  _header_3 "Sentry prerequisites"

  # Manual and required: install the agent skills.
  _prereq_manual npx "npx (for installing Sentry agent skills)"

  # Optional.
  if command -v curl &>/dev/null; then
    _ok "curl (for the endpoint reachability hint)"
  else
    _info "curl not found — endpoint reachability hint will be skipped"
  fi

  # The token is resolved by the client at launch, never stored in a config.
  if [[ -n "${SENTRY_ACCESS_TOKEN:-}" ]]; then
    _ok "SENTRY_ACCESS_TOKEN is set"
  else
    _notice "SENTRY_ACCESS_TOKEN is unset — the sentry MCP server will start but every call will fail"
  fi
}

_main
