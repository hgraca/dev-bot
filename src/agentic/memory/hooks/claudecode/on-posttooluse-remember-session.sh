#!/usr/bin/env bash
# =============================================================================
# src/agentic/memory/hooks/claudecode/on-posttooluse-remember-session.sh
# Claude Code PostToolUse hook — detects successful git commits and writes
# a trigger file for the Stop hook to pick up.
#
# Register in .claude/settings.local.json:
#   "hooks": {
#     "PostToolUse": [
#       {
#         "matcher": "Bash",
#         "hooks": [
#           {
#             "type": "command",
#             "command": "bash src/agentic/memory/hooks/claudecode/on-posttooluse-remember-session.sh"
#           }
#         ]
#       }
#     ]
#   }
#
# Equivalent to OpenCode plugin:
#   on-tool_execute_after-git_commit-remember-session.ts (Phase 1)
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_output.exit_code // "1"')
WORKTREE=$(echo "$INPUT" | jq -r '.cwd // empty')

# Only react to successful git commits
if [[ "$EXIT_CODE" != "0" ]]; then
  exit 0
fi
if ! echo "$COMMAND" | grep -q 'git[[:space:]]\+commit'; then
  exit 0
fi

if [[ -z "$WORKTREE" || ! -d "$WORKTREE" ]]; then
  WORKTREE="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# ── Extract commit context ──────────────────────────────────────────────────

COMMIT_INFO=$(git -C "$WORKTREE" log -1 --format="%H%x00%s%x00%an%x00%ai" --name-only 2>/dev/null || true)
if [[ -z "$COMMIT_INFO" ]]; then
  exit 0
fi

HASH=$(echo "$COMMIT_INFO" | head -1 | cut -d$'\0' -f1)
MESSAGE=$(echo "$COMMIT_INFO" | head -1 | cut -d$'\0' -f2)
AUTHOR=$(echo "$COMMIT_INFO" | head -1 | cut -d$'\0' -f3)
TIMESTAMP=$(echo "$COMMIT_INFO" | head -1 | cut -d$'\0' -f4)
FILES=$(echo "$COMMIT_INFO" | tail -n +3 | grep -v '^$' || true)

# ── Dedup by commit hash ────────────────────────────────────────────────────

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

LOGS_DIR="${WORKTREE}/${DEVBOT_DIR}/logs"
TRIGGER_FILE="${LOGS_DIR}/remember-session.trigger.json"
PROCESSED_FILE="${LOGS_DIR}/remember-session.processed"

mkdir -p "$LOGS_DIR"

# Dedup
if [[ -f "$PROCESSED_FILE" ]] && grep -qFx "$HASH" "$PROCESSED_FILE" 2>/dev/null; then
  exit 0
fi
echo "$HASH" >> "$PROCESSED_FILE"

# ── Write trigger ───────────────────────────────────────────────────────────

FILES_JSON=$(echo "$FILES" | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))" 2>/dev/null || echo "[]")

python3 -c "
import json, sys
data = {
    'hash': '$HASH',
    'message': '''$MESSAGE''',
    'author': '$AUTHOR',
    'timestamp': '$TIMESTAMP',
    'files': json.loads('$FILES_JSON'),
    'committedAt': '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
}
with open('$TRIGGER_FILE', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null
