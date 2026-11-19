#!/usr/bin/env bash
# src/agentic/sentry/init.sh
# Set up Sentry in a project:
#   Symlink the agent skills from devbot storage to the project's
#   .opencode/skills/sentry/.
#
# The MCP server is hosted (https://mcp.sentry.dev/mcp), so there is no binary
# or harness dir to symlink. MCP auto-registration is handled by the harness
# inits from the single canonical manifest (src/agentic/sentry/mcp.json).
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


_header_3 "Sentry Init"

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
SKILLS_DIR="$(_sentry_storage_dir)/skills"
if [[ ! -d "${SKILLS_DIR}" ]] || [[ -z "$(ls -A "${SKILLS_DIR}" 2>/dev/null)" ]]; then
  _sentry_install_skills --if-missing \
    || _warn "Sentry agent skills not fetched into ${SKILLS_DIR} — npx or the network may be unavailable"
fi

_log "Sentry init complete for ${PROJECT_NAME}"

cat <<'EOF'

  Sentry MCP server wired into every enabled harness.
  Auto-registered by the harness inits from src/agentic/sentry/mcp.json, which
  points at the hosted endpoint (https://mcp.sentry.dev/mcp).
  The token comes from SENTRY_ACCESS_TOKEN in the environment at launch — it is
  never written into a config file.
EOF
