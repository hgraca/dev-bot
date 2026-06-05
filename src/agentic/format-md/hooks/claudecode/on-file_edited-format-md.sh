#!/usr/bin/env bash
# =============================================================================
# src/agentic/format-md/hooks/claudecode/on-file_edited-format-md.sh
# Claude Code PostToolUse hook for format-md.
# Reads JSON from stdin, extracts the edited file path, runs format-md if .md.
#
# Register in .claude/settings.local.json:
#   "hooks": {
#     "PostToolUse": [
#       {
#         "matcher": "Edit|Write",
#         "hooks": [
#           {
#             "type": "command",
#             "command": "bash src/agentic/format-md/hooks/claudecode/on-file_edited-format-md.sh"
#           }
#         ]
#       }
#     ]
#   }
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# Dependencies: jq (for hook input parsing), prettier (npm install -g prettier, for formatting)
# =============================================================================

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Only react to .md files
if [[ "$FILE_PATH" != *.md ]]; then
  exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PY="${REPO_ROOT}/src/agentic/format-md/tools/format-md.py"

if [[ ! -f "$PY" ]]; then
  exit 0
fi

python3 "$PY" "$FILE_PATH" 2>/dev/null || true
exit 0
