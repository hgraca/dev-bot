#!/usr/bin/env bash
# =============================================================================
# src/agentic/graphify/hooks/claudecode/on-startup-graphify-update.sh
# Claude Code Startup hook — runs graphify update in background on session
# start to ensure the knowledge graph is current.
#
# Register in .claude/settings.local.json:
#   "hooks": {
#     "Startup": [
#       {
#         "hooks": [
#           {
#             "type": "command",
#             "command": "bash src/agentic/graphify/hooks/claudecode/on-startup-graphify-update.sh"
#           }
#         ]
#       }
#     ]
#   }
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
RUNNER="${REPO_ROOT}/src/agentic/graphify/tools/graphify-update-bg.sh"

if [[ -f "$RUNNER" ]]; then
  bash "$RUNNER" "$REPO_ROOT" &
  disown 2>/dev/null || true
fi

exit 0
