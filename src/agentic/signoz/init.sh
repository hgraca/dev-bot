#!/usr/bin/env bash
# src/agentic/signoz/init.sh
# Set up SigNoz in a project:
#   Symlink agent skills from devbot storage to the project's
#   .opencode/skills/signoz/.
#
# The MCP server is no longer symlinked per harness: it runs as a shared
# machine-wide container (see docker-compose.yml) and the harness connects over
# http. MCP auto-registration is handled by the harness inits from the single
# canonical manifest (src/agentic/signoz/mcp.json), which declares the gateway
# URL.
#
# Idempotent — safe to re-run.
#
# Usage:
#   init.sh                    # init in current directory
#   init.sh /path/to/project   # init in specified project
#
# GATE: Must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd 2>/dev/null || true)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

STORAGE_DIR="$(_signoz_storage_dir)"
SKILLS_DIR="${STORAGE_DIR}/skills"

_header_3 "SigNoz Init"

# ── Validation ─────────────────────────────────────────────────────────────────

if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
  _fatal "Project directory '${1:-.}' does not exist."
  exit 1
fi

PROJECT_NAME="$(basename "${PROJECT_DIR}")"
_disabled_raw="$(_devbot_get_disabled_modules "${PROJECT_DIR}" 2>/dev/null || echo '[]')"

# ── Agent skills (opencode-only) ───────────────────────────────────────────────

if echo "${_disabled_raw}" | jq -e 'index("opencode") != null' >/dev/null 2>&1; then
  _skip "opencode disabled — skipping .opencode wiring"
else
  SKILLS_SYMLINK="${PROJECT_DIR}/.opencode/skills/signoz"

  if [[ -L "${SKILLS_SYMLINK}" ]]; then
    _skip "SigNoz skills already symlinked: .opencode/skills/signoz"
  elif [[ -d "${SKILLS_SYMLINK}" ]]; then
    _warn ".opencode/skills/signoz exists but is not a symlink — replacing."
    rm -rf "${SKILLS_SYMLINK}"
    ln -sf "${SKILLS_DIR}" "${SKILLS_SYMLINK}"
    _ok "SigNoz skills symlinked: .opencode/skills/signoz"
  elif [[ -d "${SKILLS_DIR}" ]] && [[ -n "$(ls -A "${SKILLS_DIR}" 2>/dev/null)" ]]; then
    mkdir -p "$(dirname "${SKILLS_SYMLINK}")"
    ln -sf "${SKILLS_DIR}" "${SKILLS_SYMLINK}"
    _ok "SigNoz skills symlinked: .opencode/skills/signoz → storage/signoz/skills"
  else
    _warn "SigNoz skills not found at ${SKILLS_DIR} — skipping skills wiring."
    _warn "  Run 'devbot install' first to download the skills."
  fi
fi

_log "SigNoz init complete for ${PROJECT_NAME}"

cat <<'EOF'

  SigNoz MCP server wired into every enabled harness.
  Auto-registered by the harness inits from src/agentic/signoz/mcp.json, which
  points at the shared gateway (http://127.0.0.1:18502/mcp) started by
  `devbot up` from this module's docker-compose.yml.
  The API token comes from SIGNOZ_AUTH_TOKEN in the environment when `devbot up`
  runs — it is never written into a config file.
EOF