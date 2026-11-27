#!/usr/bin/env bash
# ---
# description: Request the Copilot review on a pull request, then poll its checks and reviews until a review with findings arrives, the checks fail, or a timeout expires — printing one digest and exiting with the outcome; --until green waits on the merge gate alone. A fixup guard that is red by design never counts as a failure, and --ignore-check adds another such check
# ---
# =============================================================================
# src/agentic/github/tools/pr-watch.mcp.sh
# CLI wrapper for pr-watch — one call replaces the gh-api/sleep polling cycle.
#
# Exit codes are the result:
#   0 a review arrived, nothing to address   5 a review arrived with findings
#   3 a required check failed                6 --until green: checks pass, mergeable
#   4 the timeout expired     1 runtime error     2 usage error
#
# "Findings" is a change request, line comments, or a body that does not claim
# "no open issues" — Copilot writes a body even when it approves, and a
# dismissed or still-pending review is no verdict at all.
# --until green never requests or reads a review; it returns 6 when every check
# the base branch DECLARES required is green and the PR is mergeable. The
# declaration comes from protection and REPOSITORY rulesets, not from
# gh pr checks --required, which lists only contexts that exist — a required
# check that has not started is waited for. An ORGANISATION ruleset is not
# read (it needs admin:org), so a check required only there is invisible until
# it reports. No declared check, or an unreadable declaration, never reports
# green. A missing approval or an unresolved thread is the human's gate; a
# draft, a conflict, a stale base or an uncomputed merge state keeps waiting.
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
#   pr-watch.mcp.sh 172 --until green
#
# Dependencies: python3, gh (authenticated)
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"pr-watch","timeoutMs":3600000,"description":"Wait on one pull request and answer by exit code. Default: request the Copilot review, then poll the checks and the reviews until a review newer than this round arrives, a required check fails, or the timeout expires, printing one digest. --until green waits on the merge gate alone — it never requests or reads a review and returns only when every check the base branch declares required is green and the PR is mergeable. The declaration is read from branch protection and repository rulesets, because gh pr checks --required lists only contexts that already exist and would call a not-yet-started required check green; an organisation ruleset is not read, as it needs admin:org. No declared check, an unreadable declaration, and checks that have not registered yet all keep waiting; an unparseable answer from gh is a runtime error (exit 1). A missing approval or an unresolved thread is the human's gate; a draft, conflict, stale base or uncomputed merge state keeps waiting. A required check whose name contains fixup is red by design until the squash and never counts as a failure; --ignore-check adds another such check. --timeout must stay under the 3600s bound this server allows. Exit codes: 0 a review arrived with nothing to address (an approval or a review reporting no open issues; a dismissed or pending review is no verdict), 5 a review arrived with findings (a change request, line comments, or a body not claiming no open issues), 3 a required check failed (never an optional one), 6 all green (--until green), 4 timeout — so the caller never parses the digest.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI arguments: <number|#number|owner/repo#number|PR-URL> [--repo owner/name] [--until review|green] [--timeout seconds] [--interval seconds] [--no-request] [--ignore-check NAME] [--json]."}},"required":["args"]}}
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
