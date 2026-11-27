#!/usr/bin/env bash
# ---
# description: Report the terminal marker of a Claude Code turn to herdr
# ---
# =============================================================================
# src/agentic/agent-communication/tools/claudecode-idle.sh
# Claude Code's Stop hook has no plugin API, so the idle pass runs here: the
# transcript's last assistant turn is rebuilt as the validator's message, the
# marker is resolved from it, and herdr gets the display-only token.
#
# The opencode hosts resolve {transcript} to "", so this exits immediately
# there — their own plugin reports instead.
# =============================================================================

set -uo pipefail

TRANSCRIPT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --transcript) TRANSCRIPT="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

[[ -n "$TRANSCRIPT" && -r "$TRANSCRIPT" ]] || exit 0
[[ "${HERDR_ENV:-}" == "1" && -n "${HERDR_PANE_ID:-}" ]] || exit 0

# A subagent's transcript lives under a `subagents` directory. It shares the
# pane, so its marker is not the pane's turn end — the opencode pass skips
# child sessions for the same reason.
case "/${TRANSCRIPT}/" in
  */subagents/*) exit 0 ;;
esac

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="${MODULE_DIR}/tools/agent-communication.mcp.sh"

MESSAGE="$(python3 "${MODULE_DIR}/tools/claudecode-idle.py" --transcript "$TRANSCRIPT" 2>/dev/null)" || exit 0
[[ -n "$MESSAGE" ]] || exit 0

OUT="$(printf '%s' "$MESSAGE" | bash "$VALIDATOR" --msg-file - --require-wait 2>/dev/null)"
STATUS=$?

# A failed invocation says nothing about the turn: leave the token alone.
[[ "${STATUS}" -eq 2 ]] && exit 0

MARKER=""
if [[ "${STATUS}" -eq 0 ]]; then
  MARKER="$(printf '%s' "$OUT" | sed -n 's/.*terminal marker found: \([A-Z_]*\)$/\1/p')"
fi

# `timeout` is GNU coreutils and absent on macOS; `gtimeout` is the fallback a
# host without coreutils simply runs unaided.
_run_bounded() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 2 "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout 2 "$@"
  else
    "$@"
  fi
}

BIN="${HERDR_BIN_PATH:-herdr}"
_run_bounded "$BIN" pane report-metadata "$HERDR_PANE_ID" \
  --source devbot --token "devbot=${MARKER}" >/dev/null 2>&1 || true
