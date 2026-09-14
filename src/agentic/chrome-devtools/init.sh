#!/usr/bin/env bash
# =============================================================================
# src/agentic/chrome-devtools/init.sh
# Symlink the shared EPIPE-swallowing MCP wrapper into the project harness dirs
# so the .mcp.json / opencode.jsonc launch commands can reach it.
#
# The chrome-devtools MCP server (npx chrome-devtools-mcp) crashes with an
# unhandled EPIPE when the client closes stdio at session teardown (audit-19
# FAIL). The wrapper (src/_shared/mcp-stdio-wrapper.js) swallows it; this init
# wires the shared file under the module-specific name.
#
# Mirrors playwright/init.sh's pattern. Agentic init runs BEFORE the harness
# inits (bin/init.sh: tools -> agentic -> harnesses), so the harness dirs are
# created here rather than assumed to exist.
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

# Force-correct DEV_BOT_ROOT — _shared/functions.sh computes it one level too deep
DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../../.." && pwd)"

# shellcheck source=../../_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

_header_3 "Chrome DevTools MCP Init"

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

WRAPPER="${DEV_BOT_ROOT}/src/_shared/mcp-stdio-wrapper.js"
SERVE="${MODULE_DIR}/serve.mcp.sh"

if [[ "${_IS_OPENCODE_DISABLED}" != "true" ]]; then
  mkdir -p "${PROJECT_DIR}/.opencode"
  ln -sf "${WRAPPER}" "${PROJECT_DIR}/.opencode/chrome-devtools-mcp-wrapper.js"
  _log "Symlinked .opencode/chrome-devtools-mcp-wrapper.js"
  ln -sf "${SERVE}" "${PROJECT_DIR}/.opencode/chrome-devtools-serve.mcp.sh"
  _log "Symlinked .opencode/chrome-devtools-serve.mcp.sh"
else
  _skip "OpenCode disabled — skipping .opencode/ MCP wrapper symlink"
fi

if [[ "${_IS_CLAUDE_DISABLED}" != "true" ]]; then
  mkdir -p "${PROJECT_DIR}/.claude"
  ln -sf "${WRAPPER}" "${PROJECT_DIR}/.claude/chrome-devtools-mcp-wrapper.js"
  _log "Symlinked .claude/chrome-devtools-mcp-wrapper.js"
  ln -sf "${SERVE}" "${PROJECT_DIR}/.claude/chrome-devtools-serve.mcp.sh"
  _log "Symlinked .claude/chrome-devtools-serve.mcp.sh"
else
  _skip "Claude Code disabled — skipping .claude/ MCP wrapper symlink"
fi

# Dependency self-heal (codebase-memory pattern, T1.2): the serve launcher
# resolves a globally installed binary by explicit prefix — reinit WITHOUT a
# preceding install would register the MCP server with no binary and the
# launcher would fail with FATAL in .agents/logs/chrome-devtools-mcp.log.
if ! "${MODULE_DIR}/install.sh"; then
  _warn "chrome-devtools install reported a problem (see above) — serve launcher may fail"
fi

_log "Chrome DevTools MCP init complete for ${PROJECT_NAME}"
