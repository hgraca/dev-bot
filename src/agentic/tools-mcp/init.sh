#!/usr/bin/env bash
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd)"

source "${MODULE_DIR}/functions.sh"

# Force-correct DEV_BOT_ROOT — _shared/functions.sh computes it one level too deep
# shellcheck disable=SC2034  # consumed by the sourced _shared functions
DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../../.." && pwd)"

_header_3 "Tools MCP Init"

PROJECT_NAME="$(basename "${PROJECT_DIR}")"

# ── Check if harnesses are disabled ──────────────────────────────────────────
_IS_CLAUDE_DISABLED="false"
_IS_OPENCODE_DISABLED="false"
_disabled_modules_raw="$(_devbot_get_disabled_modules "${PROJECT_DIR}" 2>/dev/null || echo '[]')"
if echo "${_disabled_modules_raw}" | jq -e 'index("claudecode") != null' >/dev/null 2>&1; then
  _IS_CLAUDE_DISABLED="true"
fi
if echo "${_disabled_modules_raw}" | jq -e 'index("opencode") != null' >/dev/null 2>&1; then
  _IS_OPENCODE_DISABLED="true"
fi

  # The harness links this module's declared MCP assets (mcp.json "assets").
  # The harness links this module's declared MCP assets (mcp.json "assets").
_log "Tools MCP init complete for ${PROJECT_NAME}"
