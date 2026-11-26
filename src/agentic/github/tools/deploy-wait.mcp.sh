#!/usr/bin/env bash
# ---
# description: Wait for a GitHub Actions deploy run to appear and finish, then print one digest — exit codes carry the outcome
# ---
# =============================================================================
# src/agentic/github/tools/deploy-wait.mcp.sh
# CLI wrapper for deploy-wait — one call replaces a hand-rolled gh-run watch loop.
#
# Exit codes are the result:
#   0 the run succeeded      3 the run failed or was cancelled
#   4 the timeout expired    1 runtime error     2 usage error
#
# The run may be a number, #number, owner/repo#number or a run URL; without a
# run, --workflow requires --branch or --commit, so a run for another deploy is
# never taken.
#
# Usage:
#   deploy-wait.mcp.sh 1234567
#   deploy-wait.mcp.sh --workflow deploy-staging.yml --branch main
#   deploy-wait.mcp.sh --workflow deploy-staging.yml --commit abc1234 --json
#   deploy-wait.mcp.sh --workflow deploy-staging.yml --branch main --last
#
# Dependencies: python3, gh (authenticated)
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"deploy-wait","timeoutMs":3600000,"description":"Wait for a GitHub Actions deploy run to appear and finish, then print one digest. Takes a run id or URL, or --workflow plus --branch/--commit to pin the run to one deployment, including a run that does not exist yet; --last reports the newest existing run instead. Exit codes carry the outcome — 0 succeeded, 3 failed, 4 timeout — so the caller never parses the digest.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI arguments: [<run-id|#id|owner/repo#id|run-URL>] [--workflow <file|name>] [--branch <ref>] [--commit <sha>] [--last] [--repo owner/name] [--timeout seconds] [--interval seconds] [--json]."}},"required":["args"]}}
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

exec python3 "${SCRIPT_DIR}/deploy-wait.py" "$@"
