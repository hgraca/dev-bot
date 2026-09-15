#!/usr/bin/env bash
# =============================================================================
# src/agentic/codebase-memory/up.sh
# Waits for the shared codebase-memory MCP gateway (the docker compose service
# declared in this module's docker-compose.yml) to accept MCP requests, so the
# harness that starts right after `devbot up` finds it ready.
#
# Runs on `devbot up` — after docker services are started. The project directory
# is passed as $1 by bin/up.sh; falls back to cwd.
#
# Non-fatal: if the gateway never comes up, warn and continue — the harness
# starts with the codebase-memory MCP server unavailable rather than failing the
# boot.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

CODEBASE_MEMORY_MCP_URL="${CODEBASE_MEMORY_MCP_URL:-http://127.0.0.1:18504/mcp}"

main() {
  _info "codebase-memory — up"

  if ! command -v curl >/dev/null 2>&1; then
    _skip "curl not available — skipping gateway readiness check"
    return 0
  fi

  local retries=0
  while ! curl -sf -o /dev/null --max-time 2 \
    -X POST "${CODEBASE_MEMORY_MCP_URL}" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"devbot-up","version":"1"}}}'; do
    retries=$((retries + 1))
    if [[ ${retries} -ge 30 ]]; then
      _skip "codebase-memory gateway not reachable at ${CODEBASE_MEMORY_MCP_URL} after 30s — MCP server will be unavailable"
      return 0
    fi
    sleep 1
  done

  _ok "codebase-memory gateway reachable at ${CODEBASE_MEMORY_MCP_URL}"
}

main "$@"