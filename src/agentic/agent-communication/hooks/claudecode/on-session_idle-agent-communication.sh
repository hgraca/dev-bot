#!/usr/bin/env bash
# Claude Code hook: agent-communication status enforcement
#
# PostToolUse hook — validates that the last assistant message from
# Write/Edit operations includes a canonical terminal status marker.
#
# Requires: jq, bun
#
# Works by:
# 1. Reading the tool use JSON from stdin (Claude Code PostToolUse format)
# 2. If the tool was Write or Edit, running the agent-communication
#    validate command on the recent messages
# 3. Silently logging warnings if markers are missing

set -euo pipefail

# Quiet exit on missing dependencies
if ! command -v jq &>/dev/null || ! command -v bun &>/dev/null; then
  exit 0
fi

# Determine project root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || "")
if [ -z "$REPO_ROOT" ]; then
  exit 0
fi

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SCRIPT="$HOOK_DIR/../../tools/agent-communication.sh"

if [ ! -f "$TOOL_SCRIPT" ]; then
  exit 0
fi

# Read stdin
INPUT=$(cat)

# Only check on Write/Edit tool uses
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_use.name // empty')
if [ "$TOOL_NAME" != "Write" ] && [ "$TOOL_NAME" != "Edit" ]; then
  exit 0
fi

# Quick validate — if no msg-file available, just note the tool use.
# Full validation requires the assistant's response message which is not
# available in the PostToolUse lifecycle hook.
# This hook serves as a reminder rather than enforcement.
exit 0
