#!/usr/bin/env bash
# ---
# description: Push the current branch, open the pull request from a body file, assign it when asked, and request the Copilot review — the commands that always happen together, in one call. `--type` publishes a finish-flow stream (memories or review improvement) under its standing title and repository, appending to its open pull request and refusing a twin.
# ---
# =============================================================================
# src/agentic/github/tools/pr-open.mcp.sh
# CLI wrapper for pr-open.py.
#
# Usage:
#   pr-open.mcp.sh --title "feat(x): do the thing" --body-file /tmp/body.md
#   pr-open.mcp.sh --title "..." --body-file body.md --base main --draft
#   pr-open.mcp.sh --title "..." --assignee @me --no-review
#   pr-open.mcp.sh --type global-memories --cwd /path/to/worktree
#   pr-open.mcp.sh --type review-improvement --body-file body.md --cwd /path
#
# It prints the branch, what the push did, whether the PR was opened, already
# open or appended to, the URL, the assignment, and the review request outcome.
#
# Exit: 0 all requested steps done, 1 git or gh failure, 2 usage.
#
# Dependencies: python3, git, gh (authenticated)
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"pr-open","description":"Push the current branch, open the pull request from a title and body file, assign it when an assignee is given, and request the Copilot review — the commands a PR session always runs — in one call. Reports the URL and skips the push, the create or the assignment when they are already done. --type publishes a finish-flow stream (review-improvement, global-memories, proj-memories) under its standing title, repository and body: it acts on the checkout given to --cwd, appends to the branch's open pull request, refuses a second standing one, and reports a twin found after creating.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI arguments: --title <text> | --type <review-improvement|global-memories|proj-memories>, [--body-file <path>] [--base <branch>] [--draft] [--assignee <login>] [--no-review] [--remote <name>] [--repo <owner/name>] [--branch <name>] [--cwd <dir>, required with --type]."}},"required":["args"]}}
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
