#!/usr/bin/env bash
# =============================================================================
# src/agentic/format-yml/hooks/claudecode/on-file_edited-format-yml.sh
# Claude Code PostToolUse hook for format-yml.
# Reads JSON from stdin, extracts the edited file path, runs format-yml if .yml/.yaml.
#
# Register in .claude/settings.local.json:
#   "hooks": {
#     "PostToolUse": [
#       {
#         "matcher": "Edit|Write",
#         "hooks": [
#           {
#             "type": "command",
#             "command": "bash src/agentic/format-yml/hooks/claudecode/on-file_edited-format-yml.sh"
#           }
#         ]
#       }
#     ]
#   }
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# Dependencies: prettier (npm install -g prettier)
# =============================================================================

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Only react to .yml and .yaml files
if [[ "$FILE_PATH" != *.yml && "$FILE_PATH" != *.yaml ]]; then
  exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PY="${REPO_ROOT}/src/agentic/format-yml/tools/format-yml.py"

if [[ ! -f "$PY" ]]; then
  exit 0
fi

python3 "$PY" "$FILE_PATH" 2>/dev/null || true
exit 0
