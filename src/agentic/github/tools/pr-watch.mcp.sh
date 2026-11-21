#!/usr/bin/env bash
# ---
# description: Request the Copilot review on a pull request, then poll its checks and reviews until a review with findings arrives, the checks fail, or a timeout expires — printing one digest and exiting with the outcome
# ---
# =============================================================================
# src/agentic/github/tools/pr-watch.mcp.sh
# CLI wrapper for pr-watch — one call replaces the gh-api/sleep polling cycle.
#
# Exit codes are the result:
#   0 a review arrived        3 the checks failed
#   4 the timeout expired     1 runtime error     2 usage error
#
# Usage:
#   pr-watch.mcp.sh 172
#   pr-watch.mcp.sh 172 --repo GET-E/dev-bot --timeout 600 --interval 30
#   pr-watch.mcp.sh 172 --no-request --json
#
# Dependencies: python3, gh (authenticated)
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"pr-watch","description":"Drive the Copilot review cycle for one pull request: request the review, poll the PR checks and the reviews endpoint until a review with findings appears, the checks fail, or the timeout expires, then print one digest. Exit codes carry the outcome — 0 review arrived, 3 checks failed, 4 timeout — so the caller never parses the digest.","parameters":{"type":"object","properties":{"number":{"type":"string","description":"Pull request number"},"repo":{"type":"string","description":"owner/name (default: the current repository)"},"timeout":{"type":"integer","description":"Seconds to wait (default 900)"},"interval":{"type":"integer","description":"Seconds between polls (default 60)"},"no_request":{"type":"boolean","description":"Do not request a Copilot review"},"json":{"type":"boolean","description":"Emit JSON instead of markdown"}},"required":["number"]}}
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
