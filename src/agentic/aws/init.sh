#!/usr/bin/env bash
# src/agentic/aws/init.sh
# Wire AWS into a project: symlink the MCP launcher into .opencode/ (and
# .claude/ when the claudecode harness is active), copy the AWS agent rules
# into the project's memory vault, and print a note about per-project region
# overrides.
#
# Idempotent — safe to re-run.
#
# Usage:
#   init.sh                    # init in current directory
#   init.sh /path/to/project   # init in specified project

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"

_header_3 "AWS Init"

# ── Resolve claudecode-disabled status ────────────────────────────────────────
_is_claude_disabled="false"
_disabled_raw="$(_devbot_get_disabled_modules "${PROJECT_DIR}" 2>/dev/null || echo '[]')"
if echo "${_disabled_raw}" | python3 -c "import json,sys; sys.exit(0 if 'claudecode' in json.loads(sys.stdin.read()) else 1)" 2>/dev/null; then
  _is_claude_disabled="true"
fi

# ── Symlink MCP launcher ──────────────────────────────────────────────────────
mkdir -p "${PROJECT_DIR}/.opencode"
ln -sf "${MODULE_DIR}/tools/aws-mcp-proxy.sh" "${PROJECT_DIR}/.opencode/aws-mcp-proxy.sh"
_log "Symlinked .opencode/aws-mcp-proxy.sh"

if [[ "${_is_claude_disabled}" != "true" ]]; then
  mkdir -p "${PROJECT_DIR}/.claude"
  ln -sf "${MODULE_DIR}/tools/aws-mcp-proxy.sh" "${PROJECT_DIR}/.claude/aws-mcp-proxy.sh"
  _log "Symlinked .claude/aws-mcp-proxy.sh"
else
  _skip "claudecode disabled — skipping .claude/ MCP wrapper"
fi

# ── Wire rules into the project's memory vault ────────────────────────────────
_rules_src="${DEV_BOT_ROOT}/storage/aws/rules/aws-agent-rules.md"
_memory_dir="${PROJECT_DIR}/$(_devbot_get_project_dir "${PROJECT_DIR}")/memory/active"

if [[ -f "${_rules_src}" ]]; then
  mkdir -p "${_memory_dir}"
  cp "${_rules_src}" "${_memory_dir}/aws-agent-rules.md"
  _log "Copied aws-agent-rules.md → ${_memory_dir}/aws-agent-rules.md"
else
  _warn "AWS rules not found at ${_rules_src} — run 'devbot install' first"
fi

# ── Config-override note ──────────────────────────────────────────────────────
_notice "AWS region is set globally (.devbot.global.jsonc → aws_region)."
_notice "To use a different region for THIS project, add to .devbot.project.jsonc:"
_notice '  "aws_region": "<region>"'

_log "AWS init complete for $(basename "${PROJECT_DIR}")"
