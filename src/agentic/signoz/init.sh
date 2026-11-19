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


_header_3 "SigNoz Init"

# ── Validation ─────────────────────────────────────────────────────────────────

if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
  _fatal "Project directory '${1:-.}' does not exist."
  exit 1
fi

PROJECT_NAME="$(basename "${PROJECT_DIR}")"
_disabled_raw="$(_devbot_get_disabled_modules "${PROJECT_DIR}" 2>/dev/null || echo '[]')"

# ── Agent skills (opencode-only) ───────────────────────────────────────────────
#
# install/update fetch machine-wide; a project that
# enables the module must not stay wired to nothing.
SKILLS_DIR="$(_signoz_storage_dir)/skills"
if [[ ! -d "${SKILLS_DIR}" ]] || [[ -z "$(ls -A "${SKILLS_DIR}" 2>/dev/null)" ]]; then
  _signoz_install_skills --if-missing \
    || _warn "SigNoz agent skills not fetched into ${SKILLS_DIR} — npx or the network may be unavailable"
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
