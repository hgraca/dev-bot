#!/usr/bin/env bash
# =============================================================================
# src/agentic/auto-recover/hooks/claudecode/on-posttooluse-auto-recover.sh
# Claude Code PostToolUse hook — detects transient errors in tool output
# and writes a trigger file for the Stop hook to pick up.
#
# Register in .claude/settings.local.json alongside the Stop hook:
#   "hooks": {
#     "PostToolUse": [
#       {
#         "matcher": "Bash",
#         "hooks": [
#           {
#             "type": "command",
#             "command": "bash src/agentic/auto-recover/hooks/claudecode/on-posttooluse-auto-recover.sh"
#           }
#         ]
#       }
#     ],
#     "Stop": [ ... ]
#   }
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

INPUT=$(cat)
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_output.exit_code // 0')
STDERR=$(echo "$INPUT" | jq -r '.tool_output.stderr // ""')
WORKTREE=$(echo "$INPUT" | jq -r '.cwd // empty')

if [[ "$EXIT_CODE" == "0" ]]; then
  exit 0
fi

if [[ -z "$STDERR" ]]; then
  exit 0
fi

TRANSIENT_RE="MidStreamFallbackError|APIConnectionError|OpenAIException|ECONNRESET|ETIMEDOUT|socket hang up|stream closed|stream aborted|fetch failed|overloaded|assistant message prefill|must end with a user message|SSE read timed out"

if ! echo "$STDERR" | grep -qiE "$TRANSIENT_RE"; then
  exit 0
fi

# ── Write trigger ───────────────────────────────────────────────────────────

if [[ -z "$WORKTREE" || ! -d "$WORKTREE" ]]; then
  WORKTREE="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

DEVBOT_DIR=".agents"
CFG="${WORKTREE}/.devbot.project.jsonc"
if [[ -f "$CFG" ]]; then
  dd=$(python3 -c "
import json, sys
with open('$CFG') as f:
    raw = f.read()
stripped = '\n'.join(l for l in raw.split('\n') if not l.strip().startswith('//'))
data = json.loads(stripped)
print(data.get('devbot_dir', '.agents'))
" 2>/dev/null || echo ".agents")
  [[ -n "$dd" ]] && DEVBOT_DIR="$dd"
fi

THINKING_DIR="${WORKTREE}/${DEVBOT_DIR}/memory/thinking"
SLUG=$(basename "$WORKTREE" | tr -c 'a-zA-Z0-9_-' '-' | tr '[:upper:]' '[:lower:]')
TRIGGER_FILE="${THINKING_DIR}/.auto-recover-trigger-${SLUG}"

mkdir -p "$THINKING_DIR"
echo "$STDERR" > "$TRIGGER_FILE"
