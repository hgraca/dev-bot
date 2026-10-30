#!/usr/bin/env bash
# =============================================================================
# src/agentic/sonarqube/init.sh
# Wire the SonarQube MCP launcher into the project harness dirs.
#
# The canonical manifest launches `.opencode|.claude/sonarqube-serve.mcp.sh`, so
# this init symlinks the module's launcher under that name. Agentic init runs
# BEFORE the harness inits, so the harness dirs are created here rather than
# assumed to exist (chrome-devtools pattern).
#
# Also self-heals the container image: `devbot reinit` runs this without a
# preceding `devbot install`, and the launcher cannot start without its image.
#
# The MCP entry itself ships disabled (`enabled: false`); enabling the module
# wires it, and enabling the entry starts it. Nothing runs until then.
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

_header_3 "SonarQube MCP Init"

PROJECT_NAME="$(basename "${PROJECT_DIR}")"
SERVE="${MODULE_DIR}/serve.mcp.sh"

_disabled_raw="$(_devbot_get_disabled_modules "${PROJECT_DIR}" 2>/dev/null || echo '[]')"

if echo "${_disabled_raw}" | jq -e 'index("opencode") != null' >/dev/null 2>&1; then
  _skip "OpenCode disabled — skipping .opencode/ launcher symlink"
else
  mkdir -p "${PROJECT_DIR}/.opencode"
  ln -sf "${SERVE}" "${PROJECT_DIR}/.opencode/sonarqube-serve.mcp.sh"
  _ok "Symlinked .opencode/sonarqube-serve.mcp.sh"
fi

if echo "${_disabled_raw}" | jq -e 'index("claudecode") != null' >/dev/null 2>&1; then
  _skip "Claude Code disabled — skipping .claude/ launcher symlink"
else
  mkdir -p "${PROJECT_DIR}/.claude"
  ln -sf "${SERVE}" "${PROJECT_DIR}/.claude/sonarqube-serve.mcp.sh"
  _ok "Symlinked .claude/sonarqube-serve.mcp.sh"
fi

if [[ -z "${SONARQUBE_TOKEN:-}" ]]; then
  _notice "SONARQUBE_TOKEN is unset — the MCP server will fail to authenticate when enabled"
fi

if ! bash "${MODULE_DIR}/install.sh"; then
  _warn "SonarQube image install reported a problem (see above) — the launcher may fail"
fi

_log "SonarQube MCP init complete for ${PROJECT_NAME}"
