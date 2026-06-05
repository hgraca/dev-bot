#!/usr/bin/env bash
# =============================================================================
# src/agentic/memory/hooks/claudecode/on-file_edited-reindex-passive-memories.sh
# Claude Code PostToolUse hook for passive memory index refresh.
# Reads JSON from stdin, extracts the edited file path, runs qmd update + embed
# if the file is a .md in latent/global/ or latent/learnings/.
#
# Register in .claude/settings.local.json:
#   "hooks": {
#     "PostToolUse": [
#       {
#         "matcher": "Edit|Write",
#         "hooks": [
#           {
#             "type": "command",
#             "command": "bash src/agentic/memory/hooks/claudecode/on-file_edited-reindex-passive-memories.sh"
#           }
#         ]
#       }
#     ]
#   }
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# Dependencies: jq (brew install jq / apt-get install jq / dnf install jq), qmd
# =============================================================================

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Only react to .md files in passive memory directories
if [[ "$FILE_PATH" != *.md ]]; then
  exit 0
fi

if [[ "$FILE_PATH" != *"/memory/latent/global"* ]] && [[ "$FILE_PATH" != *"/memory/latent/learnings"* ]]; then
  exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LOGS_DIR="${REPO_ROOT}/.agents/logs"
LOG_FILE="${LOGS_DIR}/qmd-index.log"

mkdir -p "$LOGS_DIR"

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '[%s] [QMD-INDEX] file=%s cmd="qmd update && qmd embed"\n' "$NOW" "$FILE_PATH" >> "$LOG_FILE"

if command -v qmd &>/dev/null; then
  bash -c "(qmd update && qmd embed) >> \"${LOG_FILE}\" 2>&1 &" &
  disown 2>/dev/null || true
fi

exit 0
