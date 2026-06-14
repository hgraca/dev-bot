#!/usr/bin/env bash
# =============================================================================
# src/agentic/format-json/hooks/claudecode/on-file_edited-format-json.sh
# Claude Code PostToolUse hook for format-json.
# Reads JSON from stdin, extracts the edited file path, runs format-json if .json/.jsonc.
#
# Register in .claude/settings.local.json:
#   "hooks": {
#     "PostToolUse": [
#       {
#         "matcher": "Edit|Write",
#         "hooks": [
#           {
#             "type": "command",
#             "command": "bash src/agentic/format-json/hooks/claudecode/on-file_edited-format-json.sh"
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

# Only react to .json and .jsonc files
if [[ "$FILE_PATH" != *.json && "$FILE_PATH" != *.jsonc ]]; then
  exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PY="${REPO_ROOT}/src/agentic/format-json/tools/format-json.py"

if [[ ! -f "$PY" ]]; then
  exit 0
fi

python3 "$PY" "$FILE_PATH" 2>/dev/null || true
exit 0
