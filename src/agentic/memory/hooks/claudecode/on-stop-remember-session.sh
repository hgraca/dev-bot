#!/usr/bin/env bash
# =============================================================================
# src/agentic/memory/hooks/claudecode/on-stop-remember-session.sh
# Claude Code Stop hook — reads the remember-session trigger file and outputs
# a capture prompt as session context for the next turn.
#
# Register in .claude/settings.local.json:
#   "hooks": {
#     "Stop": [
#       {
#         "hooks": [
#           {
#             "type": "command",
#             "command": "bash src/agentic/memory/hooks/claudecode/on-stop-remember-session.sh"
#           }
#         ]
#       }
#     ]
#   }
#
# Equivalent to OpenCode plugin:
#   on-tool_execute_after-git_commit-remember-session.ts (Phase 2)
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

INPUT=$(cat)
WORKTREE=$(echo "$INPUT" | jq -r '.cwd // empty')

if [[ -z "$WORKTREE" || ! -d "$WORKTREE" ]]; then
  WORKTREE="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

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

LOGS_DIR="${WORKTREE}/${DEVBOT_DIR}/logs"
TRIGGER_FILE="${LOGS_DIR}/remember-session.trigger.json"
LOCK_FILE="${LOGS_DIR}/remember-session.locks.json"
WATERMARK_FILE="${LOGS_DIR}/remember-session.watermark.json"

TRIGGER_TTL_MIN=5
LOCK_TTL_MIN=10

# ── Read trigger ────────────────────────────────────────────────────────────

if [[ ! -f "$TRIGGER_FILE" ]]; then
  exit 0
fi

TRIGGER=$(python3 -c "
import json, sys, os, time
with open('$TRIGGER_FILE') as f:
    data = json.load(f)
age = time.time() - time.mktime(time.strptime(data['committedAt'], '%Y-%m-%dT%H:%M:%SZ'))
if age > ${TRIGGER_TTL_MIN} * 60:
    os.unlink('$TRIGGER_FILE')
    sys.exit(1)
print(json.dumps(data))
" 2>/dev/null || true)

if [[ -z "$TRIGGER" ]]; then
  exit 0
fi

# ── Lock check ──────────────────────────────────────────────────────────────

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"')
NOW=$(date +%s)

if [[ -f "$LOCK_FILE" ]]; then
  LOCKED=$(python3 -c "
import json, sys, time
data = json.load(open('$LOCK_FILE'))
ts = data.get('${SESSION_ID}', '')
if not ts:
    sys.exit(1)
age = time.time() - time.mktime(time.strptime(ts, '%Y-%m-%dT%H:%M:%S.%fZ'))
sys.exit(0 if age < ${LOCK_TTL_MIN} * 60 else 1)
" 2>/dev/null && echo "locked" || echo "")
  if [[ -n "$LOCKED" ]]; then
    exit 0
  fi
fi

# ── Acquire lock ────────────────────────────────────────────────────────────

python3 -c "
import json, os, time
data = {}
if os.path.exists('$LOCK_FILE'):
    data = json.load(open('$LOCK_FILE'))
data['${SESSION_ID}'] = time.strftime('%Y-%m-%dT%H:%M:%S.') + f'{int(time.time() * 1000) % 1000:03d}Z'
json.dump(data, open('$LOCK_FILE', 'w'), indent=2)
" 2>/dev/null

# ── Read watermark ──────────────────────────────────────────────────────────

WATERMARK="none"
if [[ -f "$WATERMARK_FILE" ]]; then
  WATERMARK=$(python3 -c "
import json, sys
data = json.load(open('$WATERMARK_FILE'))
print(data.get('${SESSION_ID}', 'none'))
" 2>/dev/null || echo "none")
fi

# ── Build capture prompt ────────────────────────────────────────────────────

HASH=$(echo "$TRIGGER" | python3 -c "import json,sys; print(json.load(sys.stdin)['hash'])" 2>/dev/null)
MESSAGE=$(echo "$TRIGGER" | python3 -c "import json,sys; print(json.load(sys.stdin)['message'])" 2>/dev/null)
AUTHOR=$(echo "$TRIGGER" | python3 -c "import json,sys; print(json.load(sys.stdin)['author'])" 2>/dev/null)
TIMESTAMP=$(echo "$TRIGGER" | python3 -c "import json,sys; print(json.load(sys.stdin)['timestamp'])" 2>/dev/null)
FILES=$(echo "$TRIGGER" | python3 -c "import json,sys; print('\n'.join('  - ' + f for f in json.load(sys.stdin)['files']))" 2>/dev/null || echo "  (no files listed)")

cat <<EOF

[DevBot-RememberSession-PostCommit]

Invoke the \`remember-session\` skill, execute its steps exactly ONCE, then end your response.

Capture everything new and worthwhile since the timestamp provided below, or from the beginning of the session if no timestamp is provided.

A git commit just completed:
- Hash: $HASH
- Message: $MESSAGE
- Author: $AUTHOR
- Timestamp: $TIMESTAMP
- Files changed:
$FILES

Last capture watermark: $WATERMARK

Use the commit details above as additional context for what work was just committed.

Do NOT emit \`<skill>...</skill>\` text markers.
Do NOT re-invoke the skill tool a second time.

SILENCE RULES (this is an automated post-commit capture — the user does not want commentary):
- Emit ZERO narrative text. Tool calls only.
- No status lines ("Nothing to capture", "Captured X").
- No headers, no preambles, no recaps, no closing summary.
- End the response immediately after the last tool call completes.
EOF

# ── Cleanup ─────────────────────────────────────────────────────────────────

rm -f "$TRIGGER_FILE"
