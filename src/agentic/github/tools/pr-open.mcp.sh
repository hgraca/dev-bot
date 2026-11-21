#!/usr/bin/env bash
# ---
# description: Push the current branch, open the pull request from a body file, and request the Copilot review — three commands that always happen together, in one call
# ---
# =============================================================================
# src/agentic/github/tools/pr-open.mcp.sh
# CLI wrapper for pr-open.py.
#
# Usage:
#   pr-open.mcp.sh --title "feat(x): do the thing" --body-file /tmp/body.md
#   pr-open.mcp.sh --title "..." --body-file body.md --base main --draft
#   pr-open.mcp.sh --title "..." --no-review
#
# It prints the branch, what the push did, whether the PR was opened or already
# open, the URL, and the review request outcome.
#
# Exit: 0 opened/already open, 1 git or gh failure, 2 usage.
#
# Dependencies: python3, git, gh (authenticated)
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"pr-open","description":"Push the current branch, open the pull request from a title and body file, and request the Copilot review — the three commands a PR session always runs — in one call. Reports the URL and skips the push or the create when they are already done.","parameters":{"type":"object","properties":{"title":{"type":"string","description":"Pull request title"},"body_file":{"type":"string","description":"File holding the PR body"},"base":{"type":"string","description":"Base branch (default: the repository's)"},"draft":{"type":"boolean","description":"Open as a draft"},"no_review":{"type":"boolean","description":"Do not request the Copilot review"}},"required":["title"]}}
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

exec python3 "${SCRIPT_DIR}/pr-open.py" "$@"
