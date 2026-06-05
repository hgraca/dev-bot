#!/usr/bin/env bash
# =============================================================================
# src/agentic/graphify/hooks/claudecode/on-stop-graphify-update.sh
# Claude Code Stop hook — Phase 2 of two-stage graphify update.
# Reads the trigger file written by Phase 1 and spawns graphify update in
# background. Discards stale triggers (older than 5 min).
#
# Register in .claude/settings.local.json:
#   "hooks": {
#     "Stop": [
#       {
#         "hooks": [
#           {
#             "type": "command",
#             "command": "bash src/agentic/graphify/hooks/claudecode/on-stop-graphify-update.sh"
#           }
#         ]
#       }
#     ]
#   }
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# Dependencies: jq
# =============================================================================

set -euo pipefail

INPUT=$(cat)

# ── Resolve project root ────────────────────────────────────────────────────

WORKTREE=$(echo "$INPUT" | jq -r '.cwd // empty')
if [[ -z "$WORKTREE" || ! -d "$WORKTREE" ]]; then
  WORKTREE="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# ── Read trigger ────────────────────────────────────────────────────────────

TRIGGER_FILE="${WORKTREE}/graphify-out/.graphify-commit-trigger.json"

if [[ ! -f "$TRIGGER_FILE" ]]; then
  exit 0
fi

TRIGGER_TTL_MIN=5

# Check TTL — discard stale triggers
TRIGGER=$(python3 -c "
import json, sys, os, time
with open('$TRIGGER_FILE') as f:
    data = json.load(f)
age = time.time() - time.mktime(time.strptime(data['committedAt'], '%Y-%m-%dT%H:%M:%SZ'))
if age > ${TRIGGER_TTL_MIN} * 60:
    os.unlink('$TRIGGER_FILE')
    sys.exit(1)
print(data['hash'])
" 2>/dev/null || true)

if [[ -z "$TRIGGER" ]]; then
  exit 0
fi

# ── Run graphify update ─────────────────────────────────────────────────────

RUNNER="${WORKTREE}/src/agentic/graphify/tools/graphify-update-bg.sh"

if [[ -f "$RUNNER" ]]; then
  bash "$RUNNER" "$WORKTREE" &
  disown 2>/dev/null || true
fi

# ── Cleanup ─────────────────────────────────────────────────────────────────

rm -f "$TRIGGER_FILE"

exit 0
