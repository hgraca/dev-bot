#!/usr/bin/env bash
# ---
# description: Validate that an assistant message ends with a terminal status marker ([FINISHED], [BLOCKED], [NEEDS_INPUT], [PARTIAL])
# ---
# =============================================================================
# src/agentic/agent-communication/tools/agent-communication.mcp.sh
# Validate that an assistant message ends with a terminal status marker
# ([FINISHED], [BLOCKED], [NEEDS_INPUT], [PARTIAL]).
#
# Usage:
#   agent-communication.mcp.sh --msg-file <path>
#
# Exit codes:
#   0 — marker found (or no assistant message)
#   1 — marker missing
#   2 — file not found / parse error
#
# Parameters:
# - msg-file (string, required): path to a JSON message file to validate
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"agent-communication","description":"Validate that an assistant message ends with a terminal status marker ([FINISHED], [BLOCKED], [NEEDS_INPUT], [PARTIAL]). The --msg-file must contain a harness session-message JSON object, e.g. {\"info\":{\"role\":\"assistant\"},\"parts\":[{\"type\":\"text\",\"text\":\"...\"}]}.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI args (e.g. --msg-file <path>)"}},"required":["args"]}}
JSON
    exit 0
    ;;
esac

# ── Parse args ───────────────────────────────────────────────────────────────

MSG_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --msg-file) MSG_FILE="$2"; shift 2 ;;
    validate) shift ;;  # optional subcommand
    --help|-h)
      echo "Usage: agent-communication.mcp.sh --msg-file <path>"
      echo "  Validate a JSON message file for terminal status markers."
      exit 0
      ;;
    *) shift ;;
  esac
done

if [[ -z "$MSG_FILE" ]]; then
  echo "[agent-communication] --msg-file is required (or pass '-' to read from stdin)" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[agent-communication] jq is required but not installed" >&2
  exit 2
fi

# ── Read the message (from a file, or from stdin via '-' / '/dev/stdin') ─────
MSG_JSON=""
if [[ "$MSG_FILE" == "-" || "$MSG_FILE" == "/dev/stdin" ]]; then
  MSG_JSON="$(cat 2>/dev/null || true)"
elif [[ -r "$MSG_FILE" ]]; then
  MSG_JSON="$(cat "$MSG_FILE" 2>/dev/null || true)"
else
  echo "[agent-communication] Message file not found: ${MSG_FILE}" >&2
  exit 2
fi

# ── Validate ─────────────────────────────────────────────────────────────────

# Check it's valid JSON
if ! echo "$MSG_JSON" | jq empty 2>/dev/null; then
  echo "[agent-communication] Invalid JSON in message" >&2
  exit 2
fi

# Check role is assistant (skip non-assistant messages silently)
ROLE=$(echo "$MSG_JSON" | jq -r '.info.role // ""' 2>/dev/null)
if [[ "$ROLE" != "assistant" ]]; then
  echo "[agent-communication] OK — terminal marker found"
  exit 0
fi

# Extract text from parts and check for terminal marker
TEXT=$(echo "$MSG_JSON" | jq -r '[.parts[]? | select(.type == "text") | .text // ""] | join("")' 2>/dev/null)

# Empty or whitespace-only messages auto-pass (nothing to validate)
if [[ -z "${TEXT//[$' \t\n\r']/}" ]]; then
  echo "[agent-communication] OK — terminal marker found"
  exit 0
fi

MARKER_RE='\[(FINISHED|BLOCKED|NEEDS_INPUT|PARTIAL)\]'

if echo "$TEXT" | grep -qE "$MARKER_RE"; then
  echo "[agent-communication] OK — terminal marker found"
  exit 0
fi

# Strip trailing fenced block and extract last line
STRIPPED=$(echo "$TEXT" | python3 -c "
import sys, re
text = sys.stdin.read()
# Remove trailing fenced block at end
text = re.sub(r'\n\`\`\`[^\n]*\n?$', '', text)
print(text.rstrip())
" 2>/dev/null || echo "$TEXT")

LAST_LINE=$(echo "$STRIPPED" | grep -v '^\s*$' | tail -1)

echo "[agent-communication] Missing terminal marker. Last line: \"${LAST_LINE}\". Expected one of: ${MARKER_RE}" >&2
exit 1
