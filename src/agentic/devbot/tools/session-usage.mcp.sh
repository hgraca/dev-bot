#!/usr/bin/env bash
# ---
# description: Report how full the calling session's context window is (tokens used, model limit, percentage)
# ---
# =============================================================================
# src/agentic/devbot/tools/session-usage.mcp.sh
# MCP tool: how full is this session's context window?
#
# Usage:
#   session-usage.mcp.sh                       # resolve the calling session
#   session-usage.mcp.sh --session ses_abc     # explicit session id
#   session-usage.mcp.sh --json                # machine-readable payload
#   session-usage.mcp.sh --harness claudecode  # force an adapter
#
# The calling session is resolved from --session, then DEV_BOT_SESSION_ID, then
# a per-harness marker file; the MCP server itself is shared by every session in
# one harness process, so it cannot infer the caller.
#
# Dependencies: python3
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"session-usage","description":"Report how full this session's context window is: context tokens used, the model's context limit, and the percentage. The calling session is resolved automatically under opencode; pass --session <id> when it cannot be resolved (in bash: echo \"$DEV_BOT_SESSION_ID\").","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"Options: [--session <id>] [--json] [--harness opencode|claudecode]"}},"required":["args"]}}
JSON
    exit 0
    ;;
esac

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
ROOT="$(cd -P "${SCRIPT_DIR}/../../../.." && pwd)"

# shellcheck source=../../../../_shared/functions.sh
source "${ROOT}/src/_shared/functions.sh"

# The harness adapter to use: an explicit override wins, otherwise detect.
PROJECT_DIR="${TOOLS_MCP_PROJECT_DIR:-$(pwd)}"
: "${DEV_BOT_SESSION_USAGE_HARNESS:=$(_devbot_get_harness "$PROJECT_DIR")}"
export DEV_BOT_SESSION_USAGE_HARNESS

exec python3 "${ROOT}/src/_shared/session_usage.py" "$@"
