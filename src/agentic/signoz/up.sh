#!/usr/bin/env bash
# =============================================================================
# src/agentic/signoz/up.sh
# Waits for the shared SigNoz MCP gateway (the docker compose service declared in
# this module's docker-compose.yml) to accept MCP requests, so the harness that
# starts right after `devbot up` finds it ready.
#
# Runs on `devbot up` — after docker services are started. The project directory
# is passed as $1 by bin/up.sh; falls back to cwd.
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

  local token_ok=true
  if [[ -z "${SIGNOZ_AUTH_TOKEN:-}" ]]; then
    token_ok=false
  fi

  if ! command -v curl >/dev/null 2>&1; then
    _skip "curl not available — skipping gateway readiness check"
    return 0
  fi

  local retries=0
  while ! curl -sf -o /dev/null --max-time 2 \
    -X POST "${SIGNOZ_MCP_URL}" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"devbot-up","version":"1"}}}'; do
    retries=$((retries + 1))
    if [[ ${retries} -ge 30 ]]; then
      _skip "signoz gateway not reachable at ${SIGNOZ_MCP_URL} after 30s — MCP server will be unavailable"
      return 0
    fi
    sleep 1
  done

  if [[ "${token_ok}" == "false" ]]; then
    _warn "signoz gateway is up but SIGNOZ_AUTH_TOKEN is unset — DEGRADED."
    _warn "  The MCP handshake succeeds without a key, but every SigNoz tool call will fail."
    _warn "  Add SIGNOZ_AUTH_TOKEN to ${DEV_BOT_ROOT}/.env and re-run 'devbot up'."
    return 0
  fi

  _ok "signoz gateway reachable at ${SIGNOZ_MCP_URL}"
}

main "$@"
