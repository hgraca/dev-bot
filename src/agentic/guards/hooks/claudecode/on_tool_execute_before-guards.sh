#!/usr/bin/env bash
# =============================================================================
# src/agentic/guards/hooks/claudecode/on_tool_execute_before-guards.sh
# Claude Code PreToolUse hook for guards.
# Reads JSON from stdin, extracts the bash command, evaluates against guard
# rules, and blocks (exit 2) if the command matches a guard.
#
# Register in .claude/settings.local.json:
#   "hooks": {
#     "PreToolUse": [
#       {
#         "matcher": "Bash",
#         "hooks": [
#           {
#             "type": "command",
#             "command": "bash src/agentic/guards/hooks/claudecode/on_tool_execute_before-guards.sh"
#           }
#         ]
#       }
#     ]
#   }
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# Dependencies: bun, jq
# =============================================================================

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../tools/guards.ts"

if [[ ! -f "$TOOL_SCRIPT" ]]; then
  exit 0
fi

# Resolve devbot root by walking up for .devbot.dist.jsonc sentinel
DEVBOT_ROOT=""
CURRENT_DIR="$(pwd)"
while true; do
  if [[ -f "${CURRENT_DIR}/.devbot.dist.jsonc" ]]; then
    DEVBOT_ROOT="$CURRENT_DIR"
    break
  fi
  PARENT="$(dirname "$CURRENT_DIR")"
  if [[ "$PARENT" == "$CURRENT_DIR" ]]; then
    break
  fi
  CURRENT_DIR="$PARENT"
done

GLOBAL_CONFIG=""
PROJECT_CONFIG=""

if [[ -n "$DEVBOT_ROOT" ]]; then
  GLOBAL_CONFIG="${DEVBOT_ROOT}/.devbot.global.jsonc"
fi

# Project config: walk up looking for .devbot.project.jsonc
CURRENT_DIR="$(pwd)"
while true; do
  if [[ -f "${CURRENT_DIR}/.devbot.project.jsonc" ]]; then
    PROJECT_CONFIG="${CURRENT_DIR}/.devbot.project.jsonc"
    break
  fi
  PARENT="$(dirname "$CURRENT_DIR")"
  if [[ "$PARENT" == "$CURRENT_DIR" ]]; then
    break
  fi
  CURRENT_DIR="$PARENT"
done

# Quick pre-check: skip if no config has guards
HAS_GUARDS=false
if [[ -n "$GLOBAL_CONFIG" && -f "$GLOBAL_CONFIG" ]]; then
  if grep -q '"guards"' "$GLOBAL_CONFIG" 2>/dev/null; then
    HAS_GUARDS=true
  fi
fi
if ! $HAS_GUARDS && [[ -n "$PROJECT_CONFIG" && -f "$PROJECT_CONFIG" ]]; then
  if grep -q '"guards"' "$PROJECT_CONFIG" 2>/dev/null; then
    HAS_GUARDS=true
  fi
fi
if ! $HAS_GUARDS; then
  exit 0
fi

# Build args for the guards tool
ARGS=("$TOOL_SCRIPT" "--command" "$COMMAND")
if [[ -n "$GLOBAL_CONFIG" ]]; then
  ARGS+=("--global-config" "$GLOBAL_CONFIG")
else
  ARGS+=("--global-config" "")
fi
ARGS+=("--project-config" "$PROJECT_CONFIG")

RESULT=$(bun "${ARGS[@]}" 2>/dev/null) || {
  exit 0  # Fail-open on tool error
}

[BLOCKED]=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('blocked', False))" 2>/dev/null || echo "False")
MESSAGE=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('message', 'Unknown guard rule'))" 2>/dev/null || echo "")

if [[ "$BLOCKED" == "True" ]]; then
  echo "{\"decision\": \"deny\", \"additionalContext\": \"Command blocked by guard rule: ${MESSAGE}\"}"
  exit 0
fi

exit 0
