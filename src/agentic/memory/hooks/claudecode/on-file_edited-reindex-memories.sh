#!/usr/bin/env bash
# =============================================================================
# src/agentic/memory/hooks/claudecode/on-file_edited-reindex-memories.sh
# Claude Code PostToolUse hook for memory index refresh.
# Reads JSON from stdin, extracts the edited file path, calls the
# reindex-memories tool if the file is a .md in the latent/ memory directory.
#
# Register in .claude/settings.local.json:
#   "hooks": {
#     "PostToolUse": [
#       {
#         "matcher": "Edit|Write",
#         "hooks": [
#           {
#             "type": "command",
#             "command": "bash src/agentic/memory/hooks/claudecode/on-file_edited-reindex-memories.sh"
#           }
#         ]
#       }
#     ]
#   }
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# Dependencies: jq (brew install jq / apt-get install jq / dnf install jq)
# =============================================================================

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Only react to .md files in the latent memory directory
if [[ "$FILE_PATH" != *.md ]]; then
  exit 0
fi

if [[ "$FILE_PATH" != *"/memory/latent"* ]]; then
  exit 0
fi

# Delegate to the reindex-memories tool
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
REFRESH_TOOL="${REPO_ROOT}/src/agentic/memory/tools/reindex-memories/reindex-memories.sh"

if [[ -f "$REFRESH_TOOL" ]]; then
  bash "$REFRESH_TOOL" >/dev/null 2>&1 &
fi

exit 0
