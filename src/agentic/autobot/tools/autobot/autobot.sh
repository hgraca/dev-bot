#!/usr/bin/env bash
# src/agentic/autobot/tools/autobot/autobot.sh
# Thin CLI wrapper — delegates to autobot.ts via bun.

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"autobot","description":"Run one AutoBot tick: Jira/GitHub follow-ups, then due prompts","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI args: tick"}},"required":["args"]}}
JSON
    exit 0
    ;;
esac

# Resolve symlinks where `readlink -f` exists; macOS bash 3.2 has none.
_src="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1 && readlink -f "$_src" >/dev/null 2>&1; then
  _src="$(readlink -f "$_src")"
fi
SCRIPT_DIR="$(cd "$(dirname "$_src")" && pwd)"

exec bun run "${SCRIPT_DIR}/autobot.ts" "$@"
