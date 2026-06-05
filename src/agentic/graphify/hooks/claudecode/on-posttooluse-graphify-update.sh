#!/usr/bin/env bash
# =============================================================================
# src/agentic/graphify/hooks/claudecode/on-posttooluse-graphify-update.sh
# Claude Code PostToolUse hook — Phase 1 of two-stage graphify update.
# Detects successful git commits and writes a trigger file for the Stop hook
# to pick up.
#
# Register in .claude/settings.local.json:
#   "hooks": {
#     "PostToolUse": [
#       {
#         "matcher": "Bash",
#         "hooks": [
#           {
#             "type": "command",
#             "command": "bash src/agentic/graphify/hooks/claudecode/on-posttooluse-graphify-update.sh"
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
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_output.exit_code // "1"')

# Only react to successful git commits
if [[ "$EXIT_CODE" != "0" ]]; then
  exit 0
fi
if ! echo "$COMMAND" | grep -q 'git[[:space:]]\+commit'; then
  exit 0
fi

# ── Resolve project root ────────────────────────────────────────────────────

WORKTREE=$(echo "$INPUT" | jq -r '.cwd // empty')
if [[ -z "$WORKTREE" || ! -d "$WORKTREE" ]]; then
  WORKTREE="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# ── Extract commit hash ─────────────────────────────────────────────────────

HASH=$(git -C "$WORKTREE" log -1 --format="%H" 2>/dev/null || true)
if [[ -z "$HASH" ]]; then
  exit 0
fi

# ── Dedup by commit hash ────────────────────────────────────────────────────

GRAPHIFY_OUT="${WORKTREE}/graphify-out"
PROCESSED_FILE="${GRAPHIFY_OUT}/.graphify-commit-processed"

mkdir -p "$GRAPHIFY_OUT"

if [[ -f "$PROCESSED_FILE" ]] && grep -qFx "$HASH" "$PROCESSED_FILE" 2>/dev/null; then
  exit 0
fi
echo "$HASH" >> "$PROCESSED_FILE"

# ── Write trigger ───────────────────────────────────────────────────────────

TRIGGER_FILE="${GRAPHIFY_OUT}/.graphify-commit-trigger.json"

python3 -c "
import json
data = {'hash': '$HASH', 'committedAt': '$(date -u +%Y-%m-%dT%H:%M:%SZ)'}
with open('$TRIGGER_FILE', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true

exit 0
