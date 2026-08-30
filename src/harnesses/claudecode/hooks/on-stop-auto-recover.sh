#!/usr/bin/env bash
# =============================================================================
# src/harnesses/claudecode/hooks/on-stop-auto-recover.sh
# Claude Code Stop hook — reads the trigger written by the PostToolUse hook and
# delegates the recovery decision + state to the shared auto-recover tool.
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

INPUT=$(cat)
WORKTREE=$(echo "$INPUT" | jq -r '.cwd // empty')

if [[ -z "$WORKTREE" || ! -d "$WORKTREE" ]]; then
  WORKTREE="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../../agentic/auto-recover/tools/auto-recover.ts"

if [[ ! -f "$TOOL_SCRIPT" ]]; then
  exit 0
fi

# ── Trigger file (written by the PostToolUse hook) ───────────────────────────

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

if [[ ! -f "$TRIGGER_FILE" ]]; then
  exit 0
fi

TRIGGER_ERR=$(cat "$TRIGGER_FILE" 2>/dev/null || true)
rm -f "$TRIGGER_FILE"

if [[ -z "$TRIGGER_ERR" ]]; then
  exit 0
fi

# ── Delegate decision + state to the shared tool ─────────────────────────────

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"')

RESULT=$(bun "$TOOL_SCRIPT" --check --session-id "$SESSION_ID" --error "$TRIGGER_ERR" --worktree "$WORKTREE" 2>/dev/null) || {
  exit 0
}

RECOVER=$(echo "$RESULT" | jq -r 'if (.recover // false) then "True" else "False" end' 2>/dev/null || echo "False")
RECOVERY_TEXT=$(echo "$RESULT" | jq -r '.recoveryText // ""' 2>/dev/null || echo "")

if [[ "$RECOVER" == "True" && -n "$RECOVERY_TEXT" ]]; then
  echo "$RECOVERY_TEXT"
  # Release the lock shortly after outputting the recovery context.
  (sleep 5 && bun "$TOOL_SCRIPT" --release --worktree "$WORKTREE" >/dev/null 2>&1) &
fi

exit 0
