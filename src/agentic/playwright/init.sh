#!/usr/bin/env bash
# =============================================================================
# src/agentic/playwright/init.sh
# Symlink the EPIPE-swallowing MCP wrapper into the project harness dirs so
# the .mcp.json / opencode.jsonc launch commands can reach it.
#
# Mirrors graphify/init.sh's symlink pattern. Agentic init runs BEFORE the
# harness inits (bin/init.sh: tools -> agentic -> harnesses), so the harness
# dirs are created here rather than assumed to exist.
#
# Idempotent — safe to re-run.
#
# Usage:
#   init.sh                    # init in current directory
#   init.sh /path/to/project   # init in specified project
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh" 2>/dev/null || true

# Force-correct DEV_BOT_ROOT — _shared/functions.sh computes it one level too deep
DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../../.." && pwd)"

# shellcheck source=../../_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

_header_3 "Playwright MCP Init"

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

# The EPIPE-swallowing wrapper is shared (src/_shared/mcp-stdio-wrapper.js) —
# chrome-devtools and codebase-index symlink the same file under their own names.
WRAPPER="${DEV_BOT_ROOT}/src/_shared/mcp-stdio-wrapper.js"

if [[ "${_IS_OPENCODE_DISABLED}" != "true" ]]; then
  mkdir -p "${PROJECT_DIR}/.opencode"
  ln -sf "${WRAPPER}" "${PROJECT_DIR}/.opencode/playwright-mcp-wrapper.js"
  _log "Symlinked .opencode/playwright-mcp-wrapper.js"
else
  _skip "OpenCode disabled — skipping .opencode/ MCP wrapper symlink"
fi

if [[ "${_IS_CLAUDE_DISABLED}" != "true" ]]; then
  mkdir -p "${PROJECT_DIR}/.claude"
  ln -sf "${WRAPPER}" "${PROJECT_DIR}/.claude/playwright-mcp-wrapper.js"
  _log "Symlinked .claude/playwright-mcp-wrapper.js"
else
  _skip "Claude Code disabled — skipping .claude/ MCP wrapper symlink"
fi

_log "Playwright MCP init complete for ${PROJECT_NAME}"
