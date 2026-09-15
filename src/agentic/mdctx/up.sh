#!/usr/bin/env bash
# =============================================================================
# src/agentic/mdctx/up.sh
# Waits for the shared mdctx MCP gateway (the docker compose service declared in
# this module's docker-compose.yml) to accept MCP requests, so the harness that
# starts right after `devbot up` finds it ready.
#
# Runs on `devbot up` — after docker services are started. The project directory
# is passed as $1 by bin/up.sh; falls back to cwd (unused here).
#
# Non-fatal: if the gateway never comes up, warn and continue — the harness
# starts with the mdctx MCP server unavailable rather than failing the boot.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

MDCTX_MCP_URL="${MDCTX_MCP_URL:-http://127.0.0.1:18501/mcp}"

main() {
  _info "mdctx — up"

  # An `if`, not `&&`: under `set -e` a short-circuited `&&` would abort here.
  if _devbot_wait_for_mcp_gateway mdctx "${MDCTX_MCP_URL}"; then
    _ok "mdctx gateway reachable at ${MDCTX_MCP_URL}"
  fi

  return 0
}

main "$@"
