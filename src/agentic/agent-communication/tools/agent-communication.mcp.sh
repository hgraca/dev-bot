#!/usr/bin/env bash
# ---
# description: Validate that an assistant message ends with a terminal status marker (markers defined by the devbot:agent-communication skill)
# ---
# =============================================================================
# src/agentic/agent-communication/tools/agent-communication.mcp.sh
# Validate that an assistant message ends with a terminal status marker.
# The canonical marker set lives in this module's skills/SKILL.md — keep
# MARKER_RE below in sync with it (the drift-guard test in tests/ enforces this).
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
{"name":"agent-communication","description":"Validate that an assistant message ends with a terminal status marker. The canonical marker set is defined by the devbot:agent-communication skill (its skills/SKILL.md). The --msg-file must contain a harness session-message JSON object, e.g. {\"info\":{\"role\":\"assistant\"},\"parts\":[{\"type\":\"text\",\"text\":\"...\"}]}.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI args (e.g. --msg-file <path>)"}},"required":["args"]}}
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

# An empty payload is not a parse error: there is simply nothing to validate.
if [[ -z "${MSG_JSON//[$' \t\n\r']/}" ]]; then
  echo "[agent-communication] OK — empty message, nothing to validate"
  exit 0
fi

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
  echo "[agent-communication] OK — empty message, nothing to validate"
  exit 0
fi

# ── Pull requests must be referenced by URL ─────────────────────────────────
# The rule lives in skills/SKILL.md ("Referencing pull requests"). It is checked
# here because density is exactly what makes an agent drop the URL for a number,
# and no amount of prose survives that pressure reliably.
PR_STATUS=0
PR_REFS=$(printf '%s' "$TEXT" | python3 -c '
import re, sys
text = sys.stdin.read()
# Fenced blocks legitimately contain bare numbers.
text = re.sub(r"```.*?```", "", text, flags=re.S)
if not re.search(r"\b(PRs?|pull[ -]requests?)\b", text, re.I):
    print("OK")
    raise SystemExit(0)
urls = {
    (m.group(1), m.group(2))
    for m in re.finditer(
        r"https://github\.com/([^/\s]+/[^/\s]+)/pull/(\d+)(?=[/?#\s)\]>]|$)", text
    )
}
# A reference may name its repository (`GET-E/core#4988`) or just the number.
refs = {
    (m.group(1) if m.group(1) else None, m.group(2))
    for m in re.finditer(r"(?:([\w.-]+/[\w.-]+))?#(\d+)\b", text)
}
# A number only satisfies a reference from the same repository, so identically
# numbered PRs in two repositories cannot cover for each other.
missing = sorted(
    ("#" + number) if repo is None else (repo + "#" + number)
    for repo, number in refs
    if not any(
        number == url_number and (repo is None or repo.lower() == url_repo.lower())
        for url_repo, url_number in urls
    )
)
print("MISSING " + ", ".join(missing) if missing else "OK")
' 2>/dev/null) || PR_STATUS=$?

# A checker that cannot run must not read as "no PRs mentioned", or the rule
# silently turns itself off on a machine without python3.
if [[ "$PR_STATUS" -ne 0 || -z "$PR_REFS" ]]; then
  echo "[agent-communication] ERROR: the PR-reference check could not run" >&2
  exit 2
fi

case "$PR_REFS" in
  MISSING*)
    echo "[agent-communication] PRs must be referenced by URL, not by number: ${PR_REFS#MISSING }" >&2
    exit 1
    ;;
esac

# Keep in sync with the canonical marker table in skills/SKILL.md (drift-guard test enforces it).
MARKER_RE='\[(FINISHED|BLOCKED|NEEDS_INPUT|PARTIAL|WAITING_FOR_PTY)\]'

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
