#!/usr/bin/env bash
# ---
# description: Request the Copilot review on a pull request, then poll its checks and reviews until a review with findings arrives, the checks fail, or a timeout expires — printing one digest and exiting with the outcome; a fixup guard that is red by design never counts as a failure, and --ignore-check adds another such check
# ---
# =============================================================================
# src/agentic/github/tools/pr-watch.mcp.sh
# CLI wrapper for pr-watch — one call replaces the gh-api/sleep polling cycle.
#
# Exit codes are the result:
#   0 a review arrived        3 the checks failed
#   4 the timeout expired     1 runtime error     2 usage error
#
# --timeout must stay under the 3600s the MCP bound allows.
#
# The pull request may be a number, #number, owner/repo#number or a PR URL;
# exit 3 comes from the required checks only, so an optional red is not a block
# and neither is a fixup guard that is red by design until the squash.
#
# Usage:
#   pr-watch.mcp.sh 172
#   pr-watch.mcp.sh 172 --repo GET-E/dev-bot --timeout 600 --interval 30
#   pr-watch.mcp.sh 172 --no-request --json
#   pr-watch.mcp.sh 172 --no-request --ignore-check deploy-check
#
# Dependencies: python3, gh (authenticated)
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"pr-watch","timeoutMs":3600000,"description":"Drive the Copilot review cycle for one pull request: request the review, poll the PR checks and the reviews until a review with findings appears, the checks fail, or the timeout expires, then print one digest. A required check whose name contains fixup is red by design until the squash and never counts as a failure; --ignore-check adds another such check. --timeout must stay under the 3600s bound this server allows. Exit codes carry the outcome — 0 review arrived, 3 checks failed, 4 timeout — so the caller never parses the digest.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI arguments: <number|#number|owner/repo#number|PR-URL> [--repo owner/name] [--timeout seconds] [--interval seconds] [--no-request] [--ignore-check NAME] [--json]."}},"required":["args"]}}
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

exec python3 "${SCRIPT_DIR}/pr-watch.py" "$@"
