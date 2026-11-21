#!/usr/bin/env bash
# ---
# description: Stage exactly the named paths and commit them in one call — never -A, never a whole tree, with --fixup support for correcting an earlier commit
# ---
# =============================================================================
# src/agentic/git/tools/commit.mcp.sh
# CLI wrapper for commit.py.
#
# The corpus showed `git add <paths> -> git commit` in 29% of sessions: two calls
# for one act. The path list and the message are still the caller's input — that
# is the work — but the act becomes one call and cannot accidentally stage the
# whole tree.
#
# Usage:
#   commit.mcp.sh --message-file /tmp/msg.txt src/a.py src/b.py
#   commit.mcp.sh -m "fix: tidy the retry loop" -- src/a.py
#   commit.mcp.sh --fixup 3a3b3313 src/a.py
#
# Exit: 0 committed, 1 git failed, 2 usage.
#
# Dependencies: python3, git
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"commit","description":"Stage exactly the named paths and commit them in one call: never a whole tree, a pathspec keeps any foreign staged entry out, and --fixup records a correction for an earlier commit.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI arguments: [--message-file <path> | -m <message> | --fixup <sha>] [--cwd <dir>] -- <paths...>."}},"required":["args"]}}
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

exec python3 "${SCRIPT_DIR}/commit.py" "$@"
