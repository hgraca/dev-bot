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
# .env before starting services. A tokenless gateway answers the MCP `initialize`
# with HTTP 401, so the probe accepts any HTTP response (accept-http) and reports
# DEGRADED for an auth/error answer rather than the misleading "not reachable".
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

  # accept-http: a tokenless gateway answers 401, which a strict handshake probe
  # would read as unreachable and retry for the full budget. rc=3 is an auth
  # rejection (DEGRADED); rc=4 is any other HTTP error, reported neutrally so a
  # 404/5xx is not misdiagnosed as a token problem.
  local rc=0
  _devbot_wait_for_mcp_gateway signoz "${SIGNOZ_MCP_URL}" "" "" 1 || rc=$?

  case "${rc}" in
    0)
      if [[ -z "${SIGNOZ_AUTH_TOKEN:-}" ]]; then
        _warn "signoz gateway is up but SIGNOZ_AUTH_TOKEN is unset — DEGRADED."
        _warn "  Add SIGNOZ_AUTH_TOKEN to ${DEV_BOT_ROOT}/.env and re-run 'devbot up'."
      else
        _ok "signoz gateway reachable at ${SIGNOZ_MCP_URL}"
      fi
      ;;
    3)
      _warn "signoz gateway answered an auth error — DEGRADED (SIGNOZ_AUTH_TOKEN unset or invalid)."
      _warn "  Add a valid SIGNOZ_AUTH_TOKEN to ${DEV_BOT_ROOT}/.env and re-run 'devbot up'."
      ;;
    4)
      _warn "signoz gateway answered an unexpected HTTP response — DEGRADED (server not ready or misconfigured)."
      ;;
    *)
      : # nothing answered — the helper already printed the not-reachable skip
      ;;
  esac

  return 0
}

main "$@"
