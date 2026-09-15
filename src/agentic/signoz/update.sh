#!/usr/bin/env bash
# src/agentic/signoz/update.sh
# Refresh the SigNoz agent skills to their latest upstream version.
#
# The MCP server is not updated here: it runs as a shared machine-wide container
# from a pinned official image (see docker-compose.yml). Bump the image tag in
# that file to move the server forward — there is no per-machine binary any more.
#
# GATE: Requires npx.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

main() {
  echo
  _info "SigNoz (update)"

  # ── Retired per-machine binary ───────────────────────────────────────────────
  # An install that predates the shared gateway still has storage/signoz/bin.
  _signoz_remove_retired_binary

  # ── Skills ───────────────────────────────────────────────────────────────────
  # Always re-fetch (unlike install.sh, which skips when present) so an update
  # actually picks up upstream changes.
  _signoz_install_skills || _warn "SigNoz skills update skipped"

  _log "SigNoz MCP server is pinned in docker-compose.yml — bump the image tag to update it"
}

main
