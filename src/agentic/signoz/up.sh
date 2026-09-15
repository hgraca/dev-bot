#!/usr/bin/env bash
# =============================================================================
# src/agentic/signoz/up.sh
# Waits for the shared SigNoz MCP gateway (the docker compose service declared in
# this module's docker-compose.yml) to accept MCP requests, so the harness that
# starts right after `devbot up` finds it ready.
#
# Runs on `devbot up` — after docker services are started. The project directory
# is passed as $1 by bin/up.sh; falls back to cwd (unused here).
#
# The API token comes from SIGNOZ_AUTH_TOKEN, which bin/up.sh loads from the repo
# .env before starting services. A missing token is reported as DEGRADED rather
# than reachable: an MCP `initialize` handshake succeeds even with an empty key,
# so probing alone cannot tell a working gateway from a useless one.
#
# Non-fatal: if the gateway never comes up, warn and continue — the harness
# starts with the signoz MCP server unavailable rather than failing the boot.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

SIGNOZ_MCP_URL="${SIGNOZ_MCP_URL:-http://127.0.0.1:18502/mcp}"

main() {
  _info "signoz — up"

  # An `if`, not `&&`: under `set -e` a short-circuited `&&` would abort here.
  if _devbot_wait_for_mcp_gateway signoz "${SIGNOZ_MCP_URL}"; then
    if [[ -z "${SIGNOZ_AUTH_TOKEN:-}" ]]; then
      _warn "signoz gateway is up but SIGNOZ_AUTH_TOKEN is unset — DEGRADED."
      _warn "  The MCP handshake succeeds without a key, but every SigNoz tool call will fail."
      _warn "  Add SIGNOZ_AUTH_TOKEN to ${DEV_BOT_ROOT}/.env and re-run 'devbot up'."
    else
      _ok "signoz gateway reachable at ${SIGNOZ_MCP_URL}"
    fi
  fi

  return 0
}

main "$@"
