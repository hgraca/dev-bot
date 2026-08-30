#!/usr/bin/env bash
# src/agentic/signoz/init.sh
# Set up SigNoz in a project:
#   1. Symlink MCP binary from devbot storage to project's .opencode/
#   2. Symlink agent skills from devbot storage to project's .opencode/skills/signoz/
#
# MCP auto-registration is handled by bin/init.sh via mcp.opencode.json.
# The mcp.opencode.json command path (.opencode/signoz-mcp-server) resolves
# to the symlink created in step 1.
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
BIN_DIR="${STORAGE_DIR}/bin"
SKILLS_DIR="${STORAGE_DIR}/skills"

_header_3 "SigNoz Init"

# ── Validation ─────────────────────────────────────────────────────────────────

if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
  _fatal "Project directory '${1:-.}' does not exist."
  exit 1
fi

if [[ ! -x "${BIN_DIR}/signoz-mcp-server" ]]; then
  _warn "SigNoz MCP binary not found at ${BIN_DIR}/signoz-mcp-server"
  _warn "  Run 'devbot install' first to download the binary."
  exit 1
fi

# SigNoz wiring is opencode-specific (.opencode/signoz-mcp-server + skills) —
# skip when opencode is disabled so .opencode/ isn't recreated.
_disabled_raw="$(_devbot_get_disabled_modules "${PROJECT_DIR}" 2>/dev/null || echo '[]')"
if echo "${_disabled_raw}" | jq -e 'index("opencode") != null' >/dev/null 2>&1; then
  _skip "opencode disabled — skipping SigNoz wiring"
  exit 0
fi

OPCODE_DIR="${PROJECT_DIR}/.opencode"
mkdir -p "${OPCODE_DIR}"

PROJECT_NAME="$(basename "${PROJECT_DIR}")"

# ── 1. Symlink MCP binary ─────────────────────────────────────────────────────

BIN_SYMLINK="${OPCODE_DIR}/signoz-mcp-server"

if [[ -L "${BIN_SYMLINK}" ]]; then
  _skip "MCP binary already symlinked: .opencode/signoz-mcp-server"
elif [[ -f "${BIN_SYMLINK}" ]]; then
  _warn ".opencode/signoz-mcp-server exists but is not a symlink — replacing."
  rm -f "${BIN_SYMLINK}"
  ln -sf "${BIN_DIR}/signoz-mcp-server" "${BIN_SYMLINK}"
  _ok "MCP binary symlinked to .opencode/signoz-mcp-server"
else
  ln -sf "${BIN_DIR}/signoz-mcp-server" "${BIN_SYMLINK}"
  _ok "MCP binary symlinked: .opencode/signoz-mcp-server → storage/signoz/bin/signoz-mcp-server"
fi

# ── 2. Symlink agent skills ────────────────────────────────────────────────────

SKILLS_SYMLINK="${OPCODE_DIR}/skills/signoz"

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

_log "SigNoz init complete for ${PROJECT_NAME}"

cat <<'EOF'

  SigNoz MCP server and skills wired.
  MCP auto-registered by bin/init.sh using mcp.opencode.json.
  To configure authentication, edit opencode.jsonc "mcp"."signoz"."environment":

    SIGNOZ_URL        — Your SigNoz instance URL
    SIGNOZ_API_KEY    — Your SigNoz API key
    SIGNOZ_SSL_VERIFY — SSL certificate verification (true/false)
    LOG_LEVEL         — Log verbosity (info, debug, warn, error)
EOF
