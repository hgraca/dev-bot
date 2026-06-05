#!/usr/bin/env bash
# =============================================================================
# src/agentic/auto-recover/hooks/claudecode/on-stop-auto-recover.sh
# Claude Code Stop hook — detects transient provider errors and signals
# the model to resume from where it left off.
#
# Register in .claude/settings.local.json:
#   "hooks": {
#     "Stop": [
#       {
#         "hooks": [
#           {
#             "type": "command",
#             "command": "bash src/agentic/auto-recover/hooks/claudecode/on-stop-auto-recover.sh"
#           }
#         ]
#       }
#     ]
#   }
#
# How it works:
#   - Reads a trigger file written by a PostToolUse hook when a bash tool
#     fails with a transient error pattern.
#   - Applies rate limiting (2 min lock, exponential cooldown, max attempts).
#   - If within limits, outputs recovery text to stdout (added as context).
#
# Equivalent to OpenCode plugin:
#   on-session_error-auto-recover.ts
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

INPUT=$(cat)
WORKTREE=$(echo "$INPUT" | jq -r '.cwd // empty')

if [[ -z "$WORKTREE" || ! -d "$WORKTREE" ]]; then
  WORKTREE="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# ── Config ──────────────────────────────────────────────────────────────────

LOCK_TTL_SEC=120
COUNTER_TTL_SEC=1800
DEFAULT_MAX_ATTEMPTS=5
COOLDOWN_BASE_SEC=5

RECOVERY_TEXT="[devbot-AutoRecover] The previous response was interrupted by a transient provider error (mid-stream connection failure). Resume the task you were working on from where it left off. Do not restart from scratch and do not explain the error — continue silently with the next concrete step."

TRANSIENT_RE="MidStreamFallbackError|APIConnectionError|OpenAIException|ECONNRESET|ETIMEDOUT|socket hang up|stream closed|stream aborted|fetch failed|overloaded|assistant message prefill|must end with a user message|SSE read timed out"

# ── DevBot dir ──────────────────────────────────────────────────────────────

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

# ── Paths ───────────────────────────────────────────────────────────────────

THINKING_DIR="${WORKTREE}/${DEVBOT_DIR}/memory/thinking"
SLUG=$(basename "$WORKTREE" | tr -c 'a-zA-Z0-9_-' '-' | tr '[:upper:]' '[:lower:]')
TRIGGER_FILE="${THINKING_DIR}/.auto-recover-trigger-${SLUG}"
LOCK_FILE="${THINKING_DIR}/.auto-recover-lock-${SLUG}"
COUNTER_FILE="${THINKING_DIR}/.auto-recover-attempts-${SLUG}.json"

# ── Read trigger ────────────────────────────────────────────────────────────

if [[ ! -f "$TRIGGER_FILE" ]]; then
  exit 0
fi

TRIGGER_ERR=$(cat "$TRIGGER_FILE" 2>/dev/null || true)
if [[ -z "$TRIGGER_ERR" ]]; then
  rm -f "$TRIGGER_FILE"
  exit 0
fi

# ── Check transient pattern ─────────────────────────────────────────────────

if ! echo "$TRIGGER_ERR" | grep -qiE "$TRANSIENT_RE"; then
  rm -f "$TRIGGER_FILE"
  exit 0
fi

# ── Lock check (2 min TTL) ──────────────────────────────────────────────────

if [[ -f "$LOCK_FILE" ]]; then
  LOCK_TS=$(cat "$LOCK_FILE" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('started', 0))" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  LOCK_AGE=$((NOW - LOCK_TS))
  if [[ $LOCK_AGE -lt $LOCK_TTL_SEC ]]; then
    exit 0
  fi
fi

# ── Counter check (max attempts + cooldown) ─────────────────────────────────

MAX_ATTEMPTS=$DEFAULT_MAX_ATTEMPTS
if [[ -f "$CFG" ]]; then
  ma=$(python3 -c "
import json, sys
with open('$CFG') as f:
    raw = f.read()
stripped = '\n'.join(l for l in raw.split('\n') if not l.strip().startswith('//'))
data = json.loads(stripped)
print(data.get('auto_recover', {}).get('max_attempts', $DEFAULT_MAX_ATTEMPTS))
" 2>/dev/null || echo "$DEFAULT_MAX_ATTEMPTS")
  [[ -n "$ma" ]] && MAX_ATTEMPTS=$ma
fi

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"')
NOW_MS=$(date +%s%3N)
COUNT=0
LAST_AT=0

if [[ -f "$COUNTER_FILE" ]]; then
  ENTRY=$(python3 -c "
import json, sys
data = json.load(open('$COUNTER_FILE'))
entry = data.get('${SESSION_ID}', {'count': 0, 'lastAt': 0})
print(f\"{entry['count']}\x1f{entry['lastAt']}\")
" 2>/dev/null || echo $'0\x1f0')
  COUNT=$(echo "$ENTRY" | cut -d$'\x1f' -f1)
  LAST_AT=$(echo "$ENTRY" | cut -d$'\x1f' -f2)
fi

if [[ $COUNT -ge $MAX_ATTEMPTS ]]; then
  rm -f "$TRIGGER_FILE"
  exit 0
fi

SINCE_LAST=$((NOW_MS - LAST_AT))
# Exponential backoff: base * 2^count (in seconds, converted to ms)
COOLDOWN_MS=$((COOLDOWN_BASE_SEC * 1000 * (2 ** COUNT)))
if [[ $LAST_AT -gt 0 && $SINCE_LAST -lt $COOLDOWN_MS ]]; then
  exit 0
fi

# ── Acquire lock and bump counter ───────────────────────────────────────────

mkdir -p "$THINKING_DIR"
python3 -c "
import json, time
with open('$LOCK_FILE', 'w') as f:
    json.dump({'started': int(time.time()), 'attempt': $(($COUNT + 1))}, f)
" 2>/dev/null

python3 -c "
import json, time, os
data = {}
if os.path.exists('$COUNTER_FILE'):
    data = json.load(open('$COUNTER_FILE'))
data['${SESSION_ID}'] = {'count': $(($COUNT + 1)), 'lastAt': int(time.time() * 1000)}
json.dump(data, open('$COUNTER_FILE', 'w'))
" 2>/dev/null

# ── Output recovery text ────────────────────────────────────────────────────

rm -f "$TRIGGER_FILE"
echo "$RECOVERY_TEXT"

# Sleep briefly then release lock
(sleep 5 && rm -f "$LOCK_FILE") &
