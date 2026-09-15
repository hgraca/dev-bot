#!/usr/bin/env bash
# =============================================================================
# src/agentic/codebase-memory/up.sh
# Waits for the shared codebase-memory MCP gateway (the docker compose service
# declared in this module's docker-compose.yml) to accept MCP requests, so the
# harness that starts right after `devbot up` finds it ready.
#
# Runs on `devbot up` — after docker services are started. The project directory
# is passed as $1 by bin/up.sh; falls back to cwd (unused here).
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

  # An `if`, not `&&`: under `set -e` a short-circuited `&&` would abort here.
  if _devbot_wait_for_mcp_gateway codebase-memory "${CODEBASE_MEMORY_MCP_URL}"; then
    _ok "codebase-memory gateway reachable at ${CODEBASE_MEMORY_MCP_URL}"
  fi

  return 0
}

main "$@"
