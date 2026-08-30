#!/usr/bin/env bash
# ---
# description: Capture a snapshot of the current git state: current branch, default branch, recent commits, working tree status, staged diff, commits unique to the current branch, and index integrity
# ---
# =============================================================================
# src/agentic/git-report/tools/git-report.mcp.sh
# CLI wrapper for the git-report tool — snapshots current git state.
# Output format: Markdown, with the following structure:
#
#   ## Git Report
#   **Current branch:** ...
#   **Default branch:** ...
#   **Default remote branch:** ...
#   ...
#
# Usage:
#   git-report.mcp.sh                                    # default: 10 recent commits
#   git-report.mcp.sh --log-count 20                     # show 20 recent commits
#
# Dependencies: python3, git
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"git-report","description":"Capture a snapshot of the current git state: current branch, default branch, recent commits, working tree status, staged diff, commits unique to the current branch, and index integrity","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"Options passed to git-report (e.g. --log-count 20)"}},"required":["args"]}}
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

exec python3 "${SCRIPT_DIR}/git-report.py" "--format" "markdown" "$@"
