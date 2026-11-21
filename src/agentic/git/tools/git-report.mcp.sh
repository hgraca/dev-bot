#!/usr/bin/env bash
# ---
# description: Capture a snapshot of the current git state — branch, default branch, recent commits, status, staged diff, branch-unique commits, index integrity — or, with --commits RANGE, one stat block per commit in a revision range
# ---
# =============================================================================
# src/agentic/git/tools/git-report.mcp.sh
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
#   git-report.mcp.sh ../sibling                         # inspect another repo/worktree
#   git-report.mcp.sh --cwd ../sibling                   # the same, by flag
#
# Dependencies: python3, git
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"git-report","description":"Capture a snapshot of a git repository's state: repository path, current branch, default branch, recent commits, working tree status, staged diff, commits unique to the current branch, and index integrity. With --commits RANGE it instead reports per-commit subject, author and stat for a revision range — one call where the agent would otherwise run git show per commit. Pass a repository path positionally or with --cwd to inspect a sibling repo or worktree.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"Options passed to git-report (e.g. --commits origin/main..HEAD, --paths src/x, --log-count 20, --cwd /path/to/repo)"}},"required":["args"]}}
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
