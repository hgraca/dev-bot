#!/usr/bin/env bash
# src/agentic/sentry/update.sh
# Refresh the Sentry agent skills to their latest upstream version.
#
# The MCP server is not updated here: it is the hosted endpoint declared in
# mcp.json, so there is no local component to move forward.
#
# GATE: Requires npx.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

main() {
  echo
  _info "Sentry (update)"

  # Always re-fetch (unlike install.sh, which skips when present) so an update
  # actually picks up upstream changes.
  _sentry_install_skills || _warn "Sentry skills update skipped"

  _log "Sentry MCP server is the hosted endpoint in mcp.json — nothing local to update"
}

main
